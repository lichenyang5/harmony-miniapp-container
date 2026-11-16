import { BusinessError } from '@kit.BasicServicesKit';
import { sensor } from '@kit.SensorServiceKit';
import { MiniAppError } from '../../core/MiniAppError';
import { NOT_SUPPORTED, PERMISSION_DENIED, SYSTEM_ERROR } from '../../core/MiniAppErrorCode';

export interface AccelerometerReading {
  x: number;
  y: number;
  z: number;
}

export type AccelerometerListener = (reading: AccelerometerReading) => void;

/** 管理单个会话的加速度计订阅，不涉及任何厂商协议。 */
export class AccelerometerTools {
  private callback?: (reading: sensor.AccelerometerResponse) => void;

  start(refreshRateMs: number, listener: AccelerometerListener): void {
    this.stop();
    const callback = (reading: sensor.AccelerometerResponse): void => {
      listener({ x: reading.x, y: reading.y, z: reading.z });
    };
    try {
      // HarmonyOS 传感器间隔单位为纳秒；VK Bridge 使用毫秒。
      sensor.on(sensor.SensorId.ACCELEROMETER, callback, { interval: refreshRateMs * 1000000 });
      this.callback = callback;
    } catch (error) {
      throw this.toMiniAppError(error as Object, '订阅加速度计失败');
    }
  }

  stop(): void {
    const callback = this.callback;
    if (callback === undefined) {
      return;
    }
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER, callback);
      this.callback = undefined;
    } catch (error) {
      throw this.toMiniAppError(error as Object, '取消加速度计订阅失败');
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
