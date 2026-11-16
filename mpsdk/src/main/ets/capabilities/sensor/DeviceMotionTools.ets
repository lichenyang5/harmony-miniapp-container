import { BusinessError } from '@kit.BasicServicesKit';
import { sensor } from '@kit.SensorServiceKit';
import { MiniAppError } from '../../core/MiniAppError';
import { NOT_SUPPORTED, PERMISSION_DENIED, SYSTEM_ERROR } from '../../core/MiniAppErrorCode';

export interface DeviceMotionReading {
  alpha: number;
  beta: number;
  gamma: number;
}

export type DeviceMotionListener = (reading: DeviceMotionReading) => void;

/** 管理单个会话的设备方向订阅，不涉及任何厂商协议。 */
export class DeviceMotionTools {
  private callback?: (reading: sensor.OrientationResponse) => void;

  start(refreshRateMs: number, listener: DeviceMotionListener): void {
    this.stop();
    const callback = (reading: sensor.OrientationResponse): void => {
      listener({ alpha: reading.alpha, beta: reading.beta, gamma: reading.gamma });
    };
    try {
      sensor.on(sensor.SensorId.ORIENTATION, callback, { interval: refreshRateMs * 1000000 });
      this.callback = callback;
    } catch (error) {
      throw this.toMiniAppError(error as Object, '订阅设备运动失败');
    }
  }

  stop(): void {
    const callback = this.callback;
    if (callback === undefined) {
      return;
    }
    try {
      sensor.off(sensor.SensorId.ORIENTATION, callback);
      this.callback = undefined;
    } catch (error) {
      throw this.toMiniAppError(error as Object, '取消设备运动订阅失败');
    }
  }

  private toMiniAppError(error: Object, message: string): MiniAppError {
    const platformError = error as BusinessError;
    if (platformError.code === 201) {
      return new MiniAppError(PERMISSION_DENIED, message, error);
    }
    if (platformError.code === 801) {
      return new MiniAppError(NOT_SUPPORTED, message, error);
    }
    return MiniAppError.from(error, SYSTEM_ERROR, message);
  }
}
