import { BusinessError } from '@kit.BasicServicesKit';
import { sensor } from '@kit.SensorServiceKit';
import { MiniAppError } from '../../core/MiniAppError';
import { NOT_SUPPORTED, PERMISSION_DENIED, SYSTEM_ERROR } from '../../core/MiniAppErrorCode';

export interface GyroscopeReading {
  x: number;
  y: number;
  z: number;
}

export type GyroscopeListener = (reading: GyroscopeReading) => void;

/** 管理单个会话的陀螺仪订阅，不涉及任何厂商协议。 */
export class GyroscopeTools {
  private callback?: (reading: sensor.GyroscopeResponse) => void;

  start(refreshRateMs: number, listener: GyroscopeListener): void {
    this.stop();
    const callback = (reading: sensor.GyroscopeResponse): void => {
      const result: GyroscopeReading = { x: reading.x, y: reading.y, z: reading.z };
      listener(result);
    };
    try {
      // HarmonyOS 传感器间隔单位为纳秒；VK Bridge 使用毫秒。
      sensor.on(sensor.SensorId.GYROSCOPE, callback, { interval: refreshRateMs * 1000000 });
      this.callback = callback;
    } catch (error) {
      throw this.toMiniAppError(error as Object, '订阅陀螺仪失败');
    }
  }

  stop(): void {
    const callback = this.callback;
    if (callback === undefined) {
      return;
    }
    try {
      sensor.off(sensor.SensorId.GYROSCOPE, callback);
      this.callback = undefined;
    } catch (error) {
      throw this.toMiniAppError(error as Object, '取消陀螺仪订阅失败');
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
