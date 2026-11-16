import { BusinessError } from '@kit.BasicServicesKit';
import { vibrator } from '@kit.SensorServiceKit';
import { MiniAppError } from '../../core/MiniAppError';
import { NOT_SUPPORTED, PERMISSION_DENIED, SYSTEM_ERROR } from '../../core/MiniAppErrorCode';

/** HarmonyOS 振动接口需要的原生参数，不包含 VK 协议字段。 */
export interface HapticEffectConfig {
  effectId: string;
  intensity: number;
  usage: vibrator.Usage;
}

/** 只调用 HarmonyOS 振动能力，不识别 VK 方法名。 */
export class HapticTools {
  static async vibrate(config: HapticEffectConfig): Promise<void> {
    try {
      const effect: vibrator.VibratePreset = {
        type: 'preset',
        effectId: config.effectId,
        count: 1,
        intensity: config.intensity
      };
      const attribute: vibrator.VibrateAttribute = { usage: config.usage };
      await vibrator.startVibration(effect, attribute);
    } catch (error) {
      const platformError = error as BusinessError;
      if (platformError.code === 201) {
        throw new MiniAppError(PERMISSION_DENIED, '振动权限被拒绝', error as Object);
      }
      if (platformError.code === 801) {
        throw new MiniAppError(NOT_SUPPORTED, '当前设备不支持振动能力', error as Object);
      }
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, '执行触感反馈失败');
    }
  }
}
