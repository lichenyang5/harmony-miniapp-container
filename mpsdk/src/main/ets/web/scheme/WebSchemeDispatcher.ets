import { MiniAppError } from '../../core/MiniAppError';
import { SdkLogger } from '../../logging/SdkLogger';
import { WebSchemeErrorCode } from './WebSchemeErrorCode';
import { WebSchemeChain, WebSchemeDecision, WebSchemeHandler, WebSchemeRequest } from './WebSchemeTypes';

/** 每次匹配独立创建节点；先消耗续传入口，防止下游重入时重复执行。 */
class WebSchemeChainNode implements WebSchemeChain {
  private continuation?: () => WebSchemeDecision;
  private violated: boolean = false;

  constructor(continuation: () => WebSchemeDecision) {
    this.continuation = continuation;
  }

  proceed(): WebSchemeDecision {
    const continuation = this.continuation;
    this.continuation = undefined;
    if (!continuation) {
      this.violated = true;
      return WebSchemeDecision.BLOCK;
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
class WebSchemeRegistration<T extends WebSchemeRequest> {
  readonly id: string;
  readonly handler: WebSchemeHandler<T>;

  constructor(handler: WebSchemeHandler<T>, id: string) {
    this.id = id;
    this.handler = handler;
  }
}

/** 与 Session、Binding 和 ArkWeb 无关的内部同步 WebView 协议分发器。 */
export class WebSchemeDispatcher<T extends WebSchemeRequest> {
  private registrations: WebSchemeRegistration<T>[] = [];
  private generation: number = 0;
  private disposed: boolean = false;
  private resetting: boolean = false;

  constructor(handlers: WebSchemeHandler<T>[]) {
    if (!Array.isArray(handlers)) {
      throw new MiniAppError(WebSchemeErrorCode.INVALID_REGISTRATION, 'Invalid WebView scheme registration');
    }
    const snapshot: WebSchemeHandler<T>[] = handlers.slice();
    const registrations: WebSchemeRegistration<T>[] = [];
    const ids: Set<string> = new Set<string>();
    try {
      for (const handler of snapshot) {
        if (!handler) {
          throw new MiniAppError(WebSchemeErrorCode.INVALID_REGISTRATION, 'Invalid WebView scheme registration');
        }
        const id: string = handler.id;
        if (typeof id !== 'string' || id.length === 0 || /[^A-Za-z0-9._-]/.test(id) ||
          typeof handler.supports !== 'function' ||
          typeof handler.handle !== 'function' ||
          (handler.reset !== undefined && typeof handler.reset !== 'function') ||
          (handler.dispose !== undefined && typeof handler.dispose !== 'function') || ids.has(id)) {
          throw new MiniAppError(WebSchemeErrorCode.INVALID_REGISTRATION, 'Invalid WebView scheme registration');
        }
        ids.add(id);
        const registration: WebSchemeRegistration<T> = new WebSchemeRegistration<T>(handler, id);
        registrations.push(registration);
      }
    } catch (error) {
      this.releaseHandlers(snapshot);
      throw new MiniAppError(WebSchemeErrorCode.INVALID_REGISTRATION, 'Invalid WebView scheme registration',
        error as Object);
    }
    // 只有完整批次校验通过后才能成为活动注册表。
    this.registrations = registrations;
  }

  dispatch(request: T): WebSchemeDecision {
    return this.dispatchFrom(request, 0, this.generation);
  }

  private dispatchFrom(request: T, start: number, generation: number): WebSchemeDecision {
    if (!this.isCurrent(generation)) {
      return WebSchemeDecision.BLOCK;
    }
    for (let index = start; index < this.registrations.length; index++) {
      const registration = this.registrations[index];
      let supported: boolean;
      try {
        supported = registration.handler.supports(request);
      } catch (_) {
        this.logFailure(registration.id, WebSchemeErrorCode.HANDLER_FAILED);
        return WebSchemeDecision.BLOCK;
      }
      if (typeof supported !== 'boolean') {
        this.consumeRejectedDecision(supported as Object);
        this.logFailure(registration.id, WebSchemeErrorCode.INVALID_DECISION);
        return WebSchemeDecision.BLOCK;
      }
      // 匹配也属于扩展调用边界，重入导致上下文失效后不能继续执行 handle。
      if (!this.isCurrent(generation)) {
        return WebSchemeDecision.BLOCK;
      }
      if (!supported) {
        continue;
      }
      const nextIndex: number = index + 1;
      const chain = new WebSchemeChainNode((): WebSchemeDecision =>
        this.dispatchFrom(request, nextIndex, generation));
      let decision: WebSchemeDecision;
      try {
        decision = registration.handler.handle(request, chain);
      } catch (_) {
        this.logFailure(registration.id, WebSchemeErrorCode.HANDLER_FAILED);
        return WebSchemeDecision.BLOCK;
      } finally {
        chain.close();
      }
      if (decision !== WebSchemeDecision.PASS && decision !== WebSchemeDecision.CONSUME &&
        decision !== WebSchemeDecision.BLOCK) {
        this.consumeRejectedDecision(decision as Object);
        this.logFailure(registration.id, WebSchemeErrorCode.INVALID_DECISION);
        return WebSchemeDecision.BLOCK;
      }
      if (!this.isCurrent(generation) || chain.isViolated()) {
        return WebSchemeDecision.BLOCK;
      }
      return decision;
    }
    return WebSchemeDecision.PASS;
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
          this.logFailure(registration.id, WebSchemeErrorCode.RESET_FAILED);
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
    const handlers: WebSchemeHandler<T>[] = [];
    for (const registration of this.registrations) {
      handlers.push(registration.handler);
    }
    this.registrations = [];
    this.releaseHandlers(handlers);
  }

  /** 失败批次也释放所有已创建实例，重复对象只释放一次。 */
  private releaseHandlers(handlers: WebSchemeHandler<T>[]): void {
    const released: Set<WebSchemeHandler<T>> = new Set<WebSchemeHandler<T>>();
    for (const handler of handlers) {
      if (!handler || released.has(handler)) {
        continue;
      }
      released.add(handler);
      try {
        if (typeof handler.dispose === 'function') {
          handler.dispose();
        }
      } catch (_) {
        // 失败批次可能包含非法元数据或抛异常的 getter，清理时不再读取 id。
        this.logFailure(undefined, WebSchemeErrorCode.DISPOSE_FAILED);
      }
    }
  }

  /** 非法异步返回仍阻止导航，仅消费原生 Promise 的拒绝，不转换为异步分发。 */
  private consumeRejectedDecision(value: Object): void {
    try {
      if (value instanceof Promise) {
        (value as Promise<Object>).catch((): void => {
        });
      }
    } catch (_) {
      // 非标准 Promise 的消费失败不得改变同步 BLOCK 边界。
    }
  }

  private logFailure(id: string | undefined, code: string): void {
    SdkLogger.warn('WebSchemeDispatcher', 'handlerFailed', { capability: id, code: code });
  }
}
