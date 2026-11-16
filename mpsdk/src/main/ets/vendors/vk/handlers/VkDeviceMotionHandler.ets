import { BridgeContext } from '../../../core/Runtime';
import { MiniAppError } from '../../../core/MiniAppError';
import { NOT_SUPPORTED, PERMISSION_DENIED } from '../../../core/MiniAppErrorCode';
import { SdkLogContext, SdkLogger } from '../../../logging/SdkLogger';
import {
  DeviceMotionListener,
  DeviceMotionReading,
  DeviceMotionTools
} from '../../../capabilities/sensor/DeviceMotionTools';
import { ParamAssert } from '../../../utils/ParamAssert';
import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';

export const VK_WEB_APP_DEVICE_MOTION_START: string = 'VKWebAppDeviceMotionStart';

export const VK_WEB_APP_DEVICE_MOTION_STOP: string = 'VKWebAppDeviceMotionStop';

export const VK_WEB_APP_DEVICE_MOTION_CHANGED: string = 'VKWebAppDeviceMotionChanged';

const DEFAULT_REFRESH_RATE_MS: number = 1000;
const MIN_REFRESH_RATE_MS: number = 20;
const MAX_REFRESH_RATE_MS: number = 1000;
const TAG: string = 'VkDeviceMotionHandler';

export interface VkDeviceMotionStartParams {
  refresh_rate?: number;
}

interface VkBooleanResult {
  result: boolean;
}

interface VkDeviceMotionChangedEvent {
  type: string;
  data: DeviceMotionReading;
}

export interface DeviceMotionSource {
  start(refreshRateMs: number, listener: DeviceMotionListener): void;

  stop(): void;
}

/** 将 VK 设备运动协议适配到会话独占的 HarmonyOS 方向传感器订阅。 */
export class VkDeviceMotionHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly source: DeviceMotionSource;
  private active: boolean = false;
  private subscribed: boolean = false;
  private disposed: boolean = false;

  constructor(context: BridgeContext, source?: DeviceMotionSource) {
    this.context = context;
    this.source = source ?? new DeviceMotionTools();
    this.context.addCleanup((): void => this.cleanup());
  }

  @VkEvent({ name: VK_WEB_APP_DEVICE_MOTION_START })
  async start(params: VkDeviceMotionStartParams): Promise<VkBooleanResult> {
    ParamAssert.assertObject(params, 'params');
    const refreshRate: number = this.refreshRate(params.refresh_rate);
    this.assertOpen();
    try {
      this.active = false;
      this.source.start(refreshRate, (reading: DeviceMotionReading): void => this.onReading(reading));
      this.subscribed = true;
      this.active = true;
      SdkLogger.info(TAG, 'started', this.logContext(VK_WEB_APP_DEVICE_MOTION_START));
      return { result: true };
    } catch (error) {
      throw this.toVkError(error as Object);
    }
  }

  @VkEvent({ name: VK_WEB_APP_DEVICE_MOTION_STOP })
  async stop(params: object): Promise<VkBooleanResult> {
    ParamAssert.assertObject(params, 'params');
    this.assertOpen();
    try {
      this.active = false;
      if (this.subscribed) {
        this.source.stop();
        this.subscribed = false;
      }
      SdkLogger.info(TAG, 'stopped', this.logContext(VK_WEB_APP_DEVICE_MOTION_STOP));
      return { result: true };
    } catch (error) {
      throw this.toVkError(error as Object);
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.cleanup();
  }

  private cleanup(): void {
    this.active = false;
    if (!this.subscribed) {
      return;
    }
    try {
      this.source.stop();
    } catch (_) {
      SdkLogger.warn(TAG, 'stopOnCleanupFailed', this.logContext(VK_WEB_APP_DEVICE_MOTION_STOP));
    } finally {
      this.subscribed = false;
    }
  }

  private refreshRate(value: number | undefined): number {
    if (value === undefined) {
      return DEFAULT_REFRESH_RATE_MS;
    }
    ParamAssert.assertOptionalNumber(value, 'refresh_rate');
    if (!Number.isInteger(value) || value < MIN_REFRESH_RATE_MS || value > MAX_REFRESH_RATE_MS) {
      throw VkBridgeError.client(VkClientErrorCode.INVALID_PARAMS);
    }
    return value;
  }

  private onReading(reading: DeviceMotionReading): void {
    if (!this.active || this.disposed || !this.isFiniteReading(reading)) {
      return;
    }
    const documentId: number = this.context.getDocumentId();
    const event: VkDeviceMotionChangedEvent = {
      type: VK_WEB_APP_DEVICE_MOTION_CHANGED,
      data: reading
    };
    this.context.send(`window.atomicBridge.postEvent(${JSON.stringify(event)})`)
      .then((sent: boolean): void => {
        if (!sent || !this.active || this.disposed || this.context.getDocumentId() !== documentId) {
          SdkLogger.warn(TAG, 'readingNotSent', this.logContext(VK_WEB_APP_DEVICE_MOTION_CHANGED));
        }
      }).catch((): void => {
      SdkLogger.warn(TAG, 'readingSendFailed', this.logContext(VK_WEB_APP_DEVICE_MOTION_CHANGED));
    });
  }

  private isFiniteReading(reading: DeviceMotionReading): boolean {
    return Number.isFinite(reading.alpha) && Number.isFinite(reading.beta) && Number.isFinite(reading.gamma);
  }

  private assertOpen(): void {
    if (this.disposed) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
  }

  private toVkError(error: Object): VkBridgeError {
    if (error instanceof VkBridgeError) {
      return error;
    }
    if (error instanceof MiniAppError) {
      if (error.code === PERMISSION_DENIED) {
        return VkBridgeError.client(VkClientErrorCode.NO_DEVICE_PERMISSION, undefined, error);
      }
      if (error.code === NOT_SUPPORTED) {
        return VkBridgeError.client(VkClientErrorCode.UNSUPPORTED_PLATFORM, undefined, error);
      }
    }
    return VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error);
  }

  private logContext(capability: string): SdkLogContext {
    return {
      sessionId: this.context.id,
      vendorId: this.context.vendorId,
      documentId: this.context.getDocumentId(),
      capability
    };
  }
}
