import { MiniAppError } from '../../../core/MiniAppError';
import { NOT_SUPPORTED, PERMISSION_DENIED } from '../../../core/MiniAppErrorCode';
import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import { HapticEffectConfig, HapticTools } from '../../../capabilities/haptic/HapticTools';
import { BridgeContext } from '../../../core/Runtime';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';

export const VK_WEB_APP_TAPTIC_IMPACT_OCCURRED: string = 'VKWebAppTapticImpactOccurred';

export const VK_WEB_APP_TAPTIC_NOTIFICATION_OCCURRED: string = 'VKWebAppTapticNotificationOccurred';

export const VK_WEB_APP_TAPTIC_SELECTION_CHANGED: string = 'VKWebAppTapticSelectionChanged';

export type HapticInvoker = (config: HapticEffectConfig) => Promise<void>;

export interface VkHapticImpactParams {
  style: string;
}

export interface VkHapticNotificationParams {
  type: string;
}

interface VkBooleanResult {
  result: boolean;
}

/** 只负责 VK 触感参数到原生振动参数的映射。 */
export class VkHapticHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly invokeHaptic: HapticInvoker;

  constructor(context: BridgeContext, invokeHaptic?: HapticInvoker) {
    this.context = context;
    this.invokeHaptic = invokeHaptic ?? ((config: HapticEffectConfig): Promise<void> =>
    HapticTools.vibrate(config));
  }

  @VkEvent({ name: VK_WEB_APP_TAPTIC_IMPACT_OCCURRED })
  async impactOccurred(params: VkHapticImpactParams): Promise<VkBooleanResult> {
    ParamAssert.assertObject(params, 'params');
    ParamAssert.assertString(params.style, 'style');
    try {
      await this.invokeHaptic(this.impact(params.style));
      const result: VkBooleanResult = { result: true };
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      if (error instanceof MiniAppError) {
        switch (error.code) {
          case PERMISSION_DENIED:
            throw VkBridgeError.client(VkClientErrorCode.NO_DEVICE_PERMISSION, undefined, error);
          case NOT_SUPPORTED:
            throw VkBridgeError.client(VkClientErrorCode.UNSUPPORTED_PLATFORM, undefined, error);
        }
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  @VkEvent({ name: VK_WEB_APP_TAPTIC_NOTIFICATION_OCCURRED })
  async notificationOccurred(params: VkHapticNotificationParams): Promise<VkBooleanResult> {
    ParamAssert.assertObject(params, 'params');
    ParamAssert.assertString(params.type, 'type');
    try {
      await this.invokeHaptic(this.notification(params.type));
      const result: VkBooleanResult = { result: true };
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      if (error instanceof MiniAppError) {
        switch (error.code) {
          case PERMISSION_DENIED:
            throw VkBridgeError.client(VkClientErrorCode.NO_DEVICE_PERMISSION, undefined, error);
          case NOT_SUPPORTED:
            throw VkBridgeError.client(VkClientErrorCode.UNSUPPORTED_PLATFORM, undefined, error);
        }
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  @VkEvent({ name: VK_WEB_APP_TAPTIC_SELECTION_CHANGED })
  async selectionChanged(params: object): Promise<VkBooleanResult> {
    ParamAssert.assertObject(params, 'params');
    try {
      const config: HapticEffectConfig = {
        effectId: 'haptic.effect.soft', intensity: 35, usage: 'touch'
      };
      await this.invokeHaptic(config);
      const result: VkBooleanResult = { result: true };
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      if (error instanceof MiniAppError) {
        switch (error.code) {
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
  }

  private impact(style: string): HapticEffectConfig {
    switch (style) {
      case 'light':
        return { effectId: 'haptic.effect.soft', intensity: 35, usage: 'touch' };
      case 'medium':
        return { effectId: 'haptic.effect.hard', intensity: 65, usage: 'touch' };
      case 'heavy':
        return { effectId: 'haptic.effect.sharp', intensity: 100, usage: 'touch' };
      default:
        throw VkBridgeError.client(VkClientErrorCode.INVALID_PARAMS);
    }
  }

  private notification(type: string): HapticEffectConfig {
    switch (type) {
      case 'error':
        return { effectId: 'haptic.notice.fail', intensity: 100, usage: 'notification' };
      case 'success':
        return { effectId: 'haptic.notice.success', intensity: 100, usage: 'notification' };
      case 'warning':
        return { effectId: 'haptic.notice.warning', intensity: 100, usage: 'notification' };
      default:
        throw VkBridgeError.client(VkClientErrorCode.INVALID_PARAMS);
    }
  }
}
