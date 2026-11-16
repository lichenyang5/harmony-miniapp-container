import { BridgeContext } from '../../../core/Runtime';
import { MiniAppError } from '../../../core/MiniAppError';
import { NOT_SUPPORTED, PERMISSION_DENIED } from '../../../core/MiniAppErrorCode';
import { SdkLogContext, SdkLogger } from '../../../logging/SdkLogger';
import {
  AccelerometerListener,
  AccelerometerReading,
  AccelerometerTools
} from '../../../capabilities/sensor/AccelerometerTools';
import { ParamAssert } from '../../../utils/ParamAssert';
import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';

export const VK_WEB_APP_ACCELEROMETER_START: string = 'VKWebAppAccelerometerStart';

export const VK_WEB_APP_ACCELEROMETER_STOP: string = 'VKWebAppAccelerometerStop';

export const VK_WEB_APP_ACCELEROMETER_CHANGED: string = 'VKWebAppAccelerometerChanged';

const DEFAULT_REFRESH_RATE_MS: number = 1000;
const MIN_REFRESH_RATE_MS: number = 20;
const MAX_REFRESH_RATE_MS: number = 1000;
const TAG: string = 'VkAccelerometerHandler';

export interface VkAccelerometerStartParams {
  refresh_rate?: number;
}

interface VkBooleanResult {
  result: boolean;
}

interface VkAccelerometerChangedEvent {
  type: string;
  data: AccelerometerReading;
}

export interface AccelerometerSource {
  start(refreshRateMs: number, listener: AccelerometerListener): void;

  stop(): void;
}

/** 将 VK 加速度计协议适配到会话独占的 HarmonyOS 传感器订阅。 */
export class VkAccelerometerHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly source: AccelerometerSource;
  private active: boolean = false;
  private subscribed: boolean = false;
  private disposed: boolean = false;

  constructor(context: BridgeContext, source?: AccelerometerSource) {
    this.context = context;
    this.source = source ?? new AccelerometerTools();
  }

  @VkEvent({ name: VK_WEB_APP_ACCELEROMETER_START })
  async start(params: VkAccelerometerStartParams): Promise<VkBooleanResult> {
    ParamAssert.assertObject(params, 'params');
    const refreshRate: number = this.refreshRate(params.refresh_rate);
    this.assertOpen();
    try {
      this.active = false;
      this.source.start(refreshRate, (reading: AccelerometerReading): void => this.onReading(reading));
      this.subscribed = true;
      this.active = true;
      SdkLogger.info(TAG, 'started', this.logContext(VK_WEB_APP_ACCELEROMETER_START));
      return { result: true };
    } catch (error) {
      throw this.toVkError(error as Object);
    }
  }

  @VkEvent({ name: VK_WEB_APP_ACCELEROMETER_STOP })
  async stop(params: object): Promise<VkBooleanResult> {
    ParamAssert.assertObject(params, 'params');
    this.assertOpen();
    try {
      this.active = false;
      if (this.subscribed) {
        this.source.stop();
        this.subscribed = false;
      }
      SdkLogger.info(TAG, 'stopped', this.logContext(VK_WEB_APP_ACCELEROMETER_STOP));
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
    this.active = false;
    if (!this.subscribed) {
      return;
    }
    try {
      this.source.stop();
    } catch (_) {
      SdkLogger.warn(TAG, 'stopOnDisposeFailed', this.logContext(VK_WEB_APP_ACCELEROMETER_STOP));
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

  private onReading(reading: AccelerometerReading): void {
    if (!this.active || this.disposed || !this.isFiniteReading(reading)) {
      return;
    }
    const event: VkAccelerometerChangedEvent = {
      type: VK_WEB_APP_ACCELEROMETER_CHANGED,
      data: reading
    };
    this.context.send(`window.atomicBridge.postEvent(${JSON.stringify(event)})`)
      .then((sent: boolean): void => {
        if (!sent) {
          SdkLogger.warn(TAG, 'readingNotSent', this.logContext(VK_WEB_APP_ACCELEROMETER_CHANGED));
        }
      }).catch((): void => {
      SdkLogger.warn(TAG, 'readingSendFailed', this.logContext(VK_WEB_APP_ACCELEROMETER_CHANGED));
    });
  }

  private isFiniteReading(reading: AccelerometerReading): boolean {
    return Number.isFinite(reading.x) && Number.isFinite(reading.y) && Number.isFinite(reading.z);
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
