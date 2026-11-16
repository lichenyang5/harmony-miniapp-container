import { MiniAppError } from '../../../core/MiniAppError';
import { NOT_SUPPORTED } from '../../../core/MiniAppErrorCode';
import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import { BridgeContext } from '../../../core/Runtime';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';

export const VK_WEB_APP_SET_SWIPE_SETTINGS: string = 'VKWebAppSetSwipeSettings';

export interface VkSwipeSettingsParams {
  history: boolean;
}

interface VkBooleanResult {
  result: boolean;
}

/** 将 VK Swipe Back 开关映射为当前会话的返回策略。 */
export class VkSwipeSettingsHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: VK_WEB_APP_SET_SWIPE_SETTINGS })
  async setSwipeSettings(params: VkSwipeSettingsParams): Promise<VkBooleanResult> {
    ParamAssert.assertObject(params, 'params');
    ParamAssert.assertBoolean(params.history, 'history');
    try {
      this.context.setSwipeBackEnabled(params.history);
      const result: VkBooleanResult = { result: true };
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      if (error instanceof MiniAppError) {
        switch (error.code) {
          case NOT_SUPPORTED:
            throw VkBridgeError.client(VkClientErrorCode.UNSUPPORTED_PLATFORM, undefined, error);
        }
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  dispose(): void {
  }
}
