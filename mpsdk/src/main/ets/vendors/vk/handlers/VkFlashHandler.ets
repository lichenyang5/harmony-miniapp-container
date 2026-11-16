import { MiniAppError } from '../../../core/MiniAppError';
import { NOT_SUPPORTED, PERMISSION_DENIED, USER_CANCELLED } from '../../../core/MiniAppErrorCode';
import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import { FlashInfo, FlashInfoProvider, FlashTools } from '../../../capabilities/flash/FlashTools';
import { BridgeContext } from '../../../core/Runtime';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';
import { ParamAssert } from '../../../utils/ParamAssert';

export const VK_WEB_APP_FLASH_GET_INFO: string = 'VKWebAppFlashGetInfo';

export const VK_WEB_APP_FLASH_SET_LEVEL: string = 'VKWebAppFlashSetLevel';

export type FlashProviderFactory = () => FlashInfoProvider;

export interface VkFlashSetLevelParams {
  level: number;
}

interface VkFlashInfoResult {
  is_available: boolean;
  level: number;
}

interface VkBooleanResult {
  result: boolean;
}

/** 只负责 VK 闪光灯协议与 HarmonyOS 闪光灯能力之间的转换。 */
export class VkFlashHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly providerFactory: FlashProviderFactory;
  private flashTools?: FlashInfoProvider;

  constructor(context: BridgeContext, providerFactory?: FlashProviderFactory) {
    this.context = context;
    this.providerFactory = providerFactory ??
      ((): FlashInfoProvider => new FlashTools(context.uiAbilityContext));
  }

  @VkEvent({ name: VK_WEB_APP_FLASH_GET_INFO })
  async getFlashInfo(_params: object): Promise<VkFlashInfoResult> {
    try {
      const info: FlashInfo = this.getFlashTools().getInfo();
      const result: VkFlashInfoResult = {
        is_available: info.isAvailable,
        level: info.level
      };
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      if (error instanceof MiniAppError) {
        switch (error.code) {
          case USER_CANCELLED:
            throw VkBridgeError.client(VkClientErrorCode.USER_DENIED, undefined, error);
          case PERMISSION_DENIED:
            throw VkBridgeError.client(VkClientErrorCode.NO_DEVICE_PERMISSION, undefined, error);
          case NOT_SUPPORTED:
            throw VkBridgeError.client(VkClientErrorCode.UNSUPPORTED_PLATFORM, undefined, error);
        }
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }


  @VkEvent({ name: VK_WEB_APP_FLASH_SET_LEVEL })
  async setFlashLevel(params: VkFlashSetLevelParams): Promise<VkBooleanResult> {
    ParamAssert.assertObject(params, 'params');
    ParamAssert.assertNumber(params.level, 'level');
    try {
      const level = params.level;
      if (level < 0 || level > 1) {
        throw VkBridgeError.client(VkClientErrorCode.INVALID_PARAMS);
      }
      await this.getFlashTools().setEnabled(level > 0);
      const result: VkBooleanResult = { result: true };
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      if (error instanceof MiniAppError) {
        switch (error.code) {
          case USER_CANCELLED:
            throw VkBridgeError.client(VkClientErrorCode.USER_DENIED, undefined, error);
          case PERMISSION_DENIED:
            throw VkBridgeError.client(VkClientErrorCode.NO_DEVICE_PERMISSION, undefined, error);
          case NOT_SUPPORTED:
            throw VkBridgeError.client(VkClientErrorCode.UNSUPPORTED_PLATFORM, undefined, error);
        }
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }


  dispose(): void {
    this.flashTools?.dispose();
    this.flashTools = undefined;
  }

  private getFlashTools(): FlashInfoProvider {
    if (this.flashTools) {
      return this.flashTools;
    }
    const tools: FlashInfoProvider = this.providerFactory();
    this.flashTools = tools;
    this.context.addCleanup((): void => {
      if (this.flashTools === tools) {
        tools.dispose();
        this.flashTools = undefined;
      }
    });
    return tools;
  }
}
