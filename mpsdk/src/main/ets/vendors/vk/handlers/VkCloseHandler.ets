import { BridgeContext } from '../../../core/Runtime';
import { assertHostForeground } from '../../../core/HostLifecycleMonitor';
import { MiniAppError } from '../../../core/MiniAppError';
import { APP_IN_BACKGROUND } from '../../../core/MiniAppErrorCode';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';
import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';

export const VK_WEB_APP_CLOSE: string = 'VKWebAppClose';

export interface VkCloseParams {
  status?: string;
  payload?: object;
}

/** 宿主定制：关闭当前原生容器，不执行 VK 网页关闭或父子小程序跳转。 */
export class VkCloseHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private disposed: boolean = false;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: VK_WEB_APP_CLOSE })
  async close(params: VkCloseParams): Promise<VkCloseParams> {
    if (this.disposed) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
    ParamAssert.assertObject(params, 'params');
    if (params.status !== undefined) {
      ParamAssert.assertEnum(params.status, 'status', ['success', 'failed']);
    }
    if (params.payload !== undefined) {
      ParamAssert.assertObject(params.payload, 'payload');
    }
    try {
      assertHostForeground(this.context.uiAbilityContext);
      if (!this.context.requestClose) {
        throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
      }
      this.context.requestClose();
      // 会话已经关闭，统一代理会丢弃此结果，不向销毁中的文档补发成功回包。
      return params;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      if (error instanceof MiniAppError && error.code === APP_IN_BACKGROUND) {
        throw VkBridgeError.client(VkClientErrorCode.BACKGROUND, undefined, error);
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  dispose(): void {
    this.disposed = true;
  }
}
