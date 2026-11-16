import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import { BridgeContext } from '../../../core/Runtime';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';
import { VkAdapter } from '../VkAdapter';

export const VK_WEB_APP_SEND_TO_CLIENT: string = 'VKWebAppSendToClient';

export interface VkClientMessageParams {
  fragment?: string;
}

interface VkBooleanResult {
  result: boolean;
}

/** 将 VK 小程序消息原样交给当前会话宿主。 */
export class VkClientMessageHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly adapter: VkAdapter;
  private disposed: boolean = false;

  constructor(context: BridgeContext, adapter: VkAdapter) {
    this.context = context;
    this.adapter = adapter;
  }

  @VkEvent({ name: VK_WEB_APP_SEND_TO_CLIENT })
  async sendToClient(params: VkClientMessageParams): Promise<VkBooleanResult> {
    if (this.disposed) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
    ParamAssert.assertObject(params, 'params');
    ParamAssert.assertOptionalString(params.fragment, 'fragment');
    try {
      this.adapter.emitClientMessage(params.fragment);
      const result: VkBooleanResult = { result: true };
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  dispose(): void {
    this.disposed = true;
  }
}
