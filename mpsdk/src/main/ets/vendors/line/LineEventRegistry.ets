import { MiniAppError } from '../../core/MiniAppError';
import { BridgeContext } from '../../core/Runtime';
import { CAPABILITY_ALREADY_REGISTERED_OR_INVALID, SESSION_CLOSED, VENDOR_LIFECYCLE_FAILED } from '../../core/MiniAppErrorCode';
import { SdkLogger } from '../../logging/SdkLogger';
import { ParamAssert } from '../../utils/ParamAssert';
import { LineFeaturePolicy } from './LineFeaturePolicy';
import { LineEventHandler } from './LineEventHandler';

/** 单会话显式注册表；只声明当前 Binding 实际接入的方法。 */
export class LineEventRegistry {
  private readonly context: BridgeContext;
  private entries: Map<string, LineEventHandler> = new Map();
  private instances: LineEventHandler[] = [];
  private extHandlerNames: string[] = [];
  private disposed: boolean = false;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  /** 校验整批后才接管；失败时传入实例仍由调用方释放。重复提交同一实例幂等。 */
  initHandler(handlers: LineEventHandler[]): void {
    if (this.disposed) {
      throw new MiniAppError(SESSION_CLOSED, 'LINE 注册表已释放');
    }
    const pending: Map<string, LineEventHandler> = new Map();
    const instances: LineEventHandler[] = [];
    for (const handler of handlers) {
      if (this.instances.indexOf(handler) >= 0 || instances.indexOf(handler) >= 0) {
        continue;
      }
      if (handler.context !== this.context) {
        throw new MiniAppError(CAPABILITY_ALREADY_REGISTERED_OR_INVALID, 'LINE 处理器上下文不匹配');
      }
      ParamAssert.assertString(handler.type, 'type', false);
      if (this.entries.has(handler.type) || pending.has(handler.type)) {
        throw new MiniAppError(CAPABILITY_ALREADY_REGISTERED_OR_INVALID, 'LINE 处理器重复注册');
      }
      pending.set(handler.type, handler);
      instances.push(handler);
      if (handler.ext) {
        this.extHandlerNames.push(handler.type)
      }
    }
    pending.forEach((handler: LineEventHandler, type: string): void => {
      this.entries.set(type, handler);
    });
    this.instances.push(...instances);
  }

  getExtHandlerNames(): string[] {
    return this.extHandlerNames;
  }

  isActive(): boolean {
    return !this.disposed;
  }

  getFeatures(): string[] {
    return this.disposed ? [] : Array.from(this.entries.keys());
  }

  getHandler(type: string): LineEventHandler | undefined {
    if (this.disposed) {
      return undefined;
    }
    return this.entries.get(type);
  }

  /** 未注册的 APK 已知方法仍按权限不足处理。 */
  isKnownMethod(type: string): boolean {
    return this.entries.has(type) || LineFeaturePolicy.isKnownMethod(type);
  }

  /** 先停用分发并清空引用，再释放所有已接管实例；清理失败互不影响。 */
  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    const instances = this.instances;
    this.instances = [];
    this.entries.clear();
    for (const handler of instances) {
      try {
        handler.dispose();
      } catch (_) {
        SdkLogger.warn('LineEventRegistry', 'disposeFailed', {
          sessionId: this.context.id, code: VENDOR_LIFECYCLE_FAILED
        });
      }
    }
  }
}
