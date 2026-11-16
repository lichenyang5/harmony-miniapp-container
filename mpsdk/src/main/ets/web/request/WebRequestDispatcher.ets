import { MiniAppError } from '../../core/MiniAppError';
import { SdkLogger } from '../../logging/SdkLogger';
import { WebRequestErrorCode } from './WebRequestErrorCode';
import { WebRequestChain, WebRequestDecision, WebRequestHandler, WebRequest } from './WebRequestTypes';

/** 每次匹配独立创建节点；先消耗续传入口，防止下游重入时重复执行。 */
class WebRequestChainNode implements WebRequestChain {
  private continuation?: () => WebRequestDecision;
  private violated: boolean = false;

  constructor(continuation: () => WebRequestDecision) {
    this.continuation = continuation;
  }

  proceed(): WebRequestDecision {
    const continuation = this.continuation;
    this.continuation = undefined;
    if (!continuation) {
      this.violated = true;
      return WebRequestDecision.BLOCK;
    }
    return continuation();
  }

  close(): void {
    // 处理器返回后清除闭包，保存的 chain 不能继续分发或持有请求上下文。
    this.continuation = undefined;
  }

  isViolated(): boolean {
    return this.violated;
  }
}

/** 注册元数据快照；请求是否匹配由处理器决定。 */
class WebRequestRegistration<T extends WebRequest> {
  readonly id: string;
  readonly handler: WebRequestHandler<T>;

  constructor(handler: WebRequestHandler<T>, id: string) {
    this.id = id;
    this.handler = handler;
  }
}

/** 与 Session、Binding 和 ArkWeb 无关的内部同步 WebView 资源请求分发器。 */
export class WebRequestDispatcher<T extends WebRequest> {
  private registrations: WebRequestRegistration<T>[] = [];
  private generation: number = 0;
  private disposed: boolean = false;
  private resetting: boolean = false;

  constructor(handlers: WebRequestHandler<T>[], hostHandlers: WebRequestHandler<T>[] = []) {
    const snapshot: WebRequestHandler<T>[] = handlers.concat(hostHandlers);
    const registrations: WebRequestRegistration<T>[] = [];
    const ids: Set<string> = new Set<string>();
    try {
      for (const handler of snapshot) {
        const id: string = handler.id;
        if (id.length === 0 || /[^A-Za-z0-9._-]/.test(id) || ids.has(id)) {
          throw new MiniAppError(WebRequestErrorCode.INVALID_REGISTRATION, 'Invalid Web resource request registration');
        }
        ids.add(id);
        const registration: WebRequestRegistration<T> = new WebRequestRegistration<T>(handler, id);
        registrations.push(registration);
      }
    } catch (error) {
      this.releaseHandlers(snapshot);
      throw new MiniAppError(WebRequestErrorCode.INVALID_REGISTRATION, 'Invalid Web resource request registration',
        error as Object);
    }
    // 只有完整批次校验通过后才能成为活动注册表。
    this.registrations = registrations;
  }

  dispatch(request: T): WebRequestDecision {
    return this.dispatchFrom(request, 0, this.generation);
  }

  private dispatchFrom(request: T, start: number, generation: number): WebRequestDecision {
    if (!this.isCurrent(generation)) {
      return WebRequestDecision.BLOCK;
    }
    for (let index = start; index < this.registrations.length; index++) {
      const registration = this.registrations[index];
      let supported: boolean;
      try {
        supported = registration.handler.supports(request);
      } catch (_) {
        this.logFailure(registration.id, WebRequestErrorCode.HANDLER_FAILED);
        return WebRequestDecision.BLOCK;
      }
      // 匹配也属于扩展调用边界，重入导致上下文失效后不能继续执行 handle。
      if (!this.isCurrent(generation)) {
        return WebRequestDecision.BLOCK;
      }
      if (!supported) {
        continue;
      }
      const nextIndex: number = index + 1;
      const chain = new WebRequestChainNode((): WebRequestDecision =>
        this.dispatchFrom(request, nextIndex, generation));
      let decision: WebRequestDecision;
      try {
        decision = registration.handler.handle(request, chain);
      } catch (_) {
        this.logFailure(registration.id, WebRequestErrorCode.HANDLER_FAILED);
        return WebRequestDecision.BLOCK;
      } finally {
        chain.close();
      }
      if (!this.isCurrent(generation) || chain.isViolated()) {
        return WebRequestDecision.BLOCK;
      }
      return decision;
    }
    return WebRequestDecision.PASS;
  }

  private isCurrent(generation: number): boolean {
    return !this.disposed && !this.resetting && generation === this.generation;
  }

  /** 使正在分发的请求失效；不认识页面或会话标识。 */
  reset(): void {
    if (this.disposed || this.resetting) {
      return;
    }
    this.generation++;
    this.resetting = true;
    try {
      for (const registration of this.registrations) {
        if (this.disposed) {
          break;
        }
        try {
          registration.handler.reset?.();
        } catch (_) {
          this.logFailure(registration.id, WebRequestErrorCode.RESET_FAILED);
        }
      }
    } finally {
      this.resetting = false;
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.generation++;
    const handlers: WebRequestHandler<T>[] = [];
    for (const registration of this.registrations) {
      handlers.push(registration.handler);
    }
    this.registrations = [];
    this.releaseHandlers(handlers);
  }

  /** 失败批次也释放所有已创建实例，重复对象只释放一次。 */
  private releaseHandlers(handlers: WebRequestHandler<T>[]): void {
    const released: Set<WebRequestHandler<T>> = new Set<WebRequestHandler<T>>();
    for (const handler of handlers) {
      if (released.has(handler)) {
        continue;
      }
      released.add(handler);
      try {
        handler.dispose?.();
      } catch (_) {
        // 清理失败批次时不再读取 id，避免诊断元数据影响资源释放。
        this.logFailure(undefined, WebRequestErrorCode.DISPOSE_FAILED);
      }
    }
  }

  private logFailure(id: string | undefined, code: string): void {
    SdkLogger.warn('WebRequestDispatcher', 'handlerFailed', { capability: id, code: code });
  }
}
