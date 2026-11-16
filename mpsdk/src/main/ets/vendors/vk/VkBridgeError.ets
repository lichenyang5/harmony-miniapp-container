import { MiniAppError } from '../../core/MiniAppError';
import { BridgeRequestId } from './JsonObjectReader';
import { VkClientErrorCode, vkClientErrorReason } from './VkClientErrorCode';

export interface VkClientErrorData {
  error_code: number;
  error_reason: string;
  error_description?: string;
}

export interface VkApiErrorData {
  error_code: number;
  error_msg: string;
  request_params: Array<Object | null>;
}

export interface VkAuthErrorData {
  error: number;
  error_reason: string;
  error_description?: Array<Object | null>;
}

export interface VkFailureData {
  error_type: string;
  error_data: object;
  request_id?: BridgeRequestId;
}

/** 错误消息仅用于原生诊断；循环业务对象不能阻止协议错误本身被创建。 */
function describeErrorData(type: string, data: object): string {
  try {
    return `${type}: ${JSON.stringify(data)}`;
  } catch (_) {
    return `${type}: [unserializable]`;
  }
}

/** 仅 VK handler 显式创建；宿主异常仍经过 Adapter 的脱敏边界。 */
export class VkBridgeError extends MiniAppError {
  private readonly type: string;
  private readonly data: object;

  private constructor(type: string, data: object, originalCause?: Object) {
    super('VK_BRIDGE_ERROR', describeErrorData(type, data), originalCause);
    this.type = type;
    this.data = data;
  }

  static client(code: VkClientErrorCode = VkClientErrorCode.UNKNOWN, description?: string,
    originalCause?: Object): VkBridgeError {
    const data: VkClientErrorData = { error_code: code, error_reason: vkClientErrorReason(code) };
    if (description !== undefined) {
      data.error_description = description;
    }
    return new VkBridgeError('client_error', data, originalCause);
  }

  static api(data: VkApiErrorData, originalCause?: Object): VkBridgeError {
    const payload: VkApiErrorData = {
      error_code: data.error_code, error_msg: data.error_msg, request_params: data.request_params
    };
    return new VkBridgeError('api_error', payload, originalCause);
  }

  static auth(data: VkAuthErrorData, originalCause?: Object): VkBridgeError {
    const payload: VkAuthErrorData = { error: data.error, error_reason: data.error_reason };
    if (data.error_description !== undefined) {
      payload.error_description = data.error_description;
    }
    return new VkBridgeError('auth_error', payload, originalCause);
  }

  toData(): VkFailureData {
    return { error_type: this.type, error_data: this.data };
  }
}
