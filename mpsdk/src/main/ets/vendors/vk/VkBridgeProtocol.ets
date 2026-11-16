import { BridgeRequestId, JsonObjectReader } from './JsonObjectReader';
import { VkBridgeError } from './VkBridgeError';
import { VkClientErrorCode } from './VkClientErrorCode';
import { MiniAppError } from '../../core/MiniAppError';
import { INVALID_ARGUMENT, MISSING_REQUIRED_PARAMS } from '../../core/MiniAppErrorCode';

/** VK 请求回包、响应和主动通知共用的事件外壳。 */
export interface VkBridgeEvent<TData extends object = object> {
  type: string;
  data: TData;
}

/** 从 VK Web Bridge 的 postMessage 中解析出的公共请求。 */
export interface VkBridgeRequest {
  method: string;
  params: object;
  requestId: BridgeRequestId | undefined;
}

export interface VkBridgeRequestParseResult {
  method: string;
  request: VkBridgeRequest | undefined;
}

/** VK Web Bridge 请求、成功回包和失败回包的唯一转换位置。 */
export class VkBridgeProtocol {
  static parseResponse(dataJson: string): VkBridgeEvent | undefined {
    let payload: Object;
    try {
      payload = JSON.parse(dataJson) as Object;
    } catch (_) {
      return undefined;
    }
    if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
      return undefined;
    }
    const values = payload as Record<string, Object>;
    const type = values['type'];
    const data = values['data'];
    if (typeof type !== 'string' || type.trim().length === 0 ||
      data === null || typeof data !== 'object' || Array.isArray(data)) {
      return undefined;
    }
    // 保留完整事件及扩展字段，交由响应方法处理。
    return payload as VkBridgeEvent;
  }

  static parseRequest(dataJson: string): VkBridgeRequestParseResult | undefined {
    let payload: Object;
    try {
      payload = JSON.parse(dataJson) as Object;
    } catch (_) {
      return undefined;
    }
    if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
      return undefined;
    }

    const values = payload as Record<string, Object>;
    if (values['type'] !== 'vk-connect' || typeof values['handler'] !== 'string') {
      return undefined;
    }
    const method = values['handler'] as string;
    const params = values['params'];
    if (params === null || typeof params !== 'object' || Array.isArray(params)) {
      return { method, request: undefined };
    }

    let requestId: BridgeRequestId | undefined;
    try {
      requestId = JsonObjectReader.fromObject(params).optionalRequestId('request_id');
    } catch (_) {
      return { method, request: undefined };
    }
    return {
      method,
      request: {
        method,
        params: params as object,
        requestId
      }
    };
  }

  static success(eventName: string, requestId: BridgeRequestId | undefined, result: object): VkBridgeEvent {
    const source = result as Record<string, Object>;
    const data: Record<string, Object> = {};
    Object.keys(source).forEach((key: string): void => {
      if (key !== 'request_id') {
        data[key] = source[key];
      }
    });
    if (requestId !== undefined) {
      data['request_id'] = requestId;
    }
    return { type: eventName, data };
  }

  static failure(eventName: string, requestId: BridgeRequestId | undefined,
    error: Object | null | undefined): VkBridgeEvent {
    let code: VkClientErrorCode = VkClientErrorCode.UNKNOWN;
    if (error instanceof MiniAppError) {
      if (error.code === MISSING_REQUIRED_PARAMS) {
        code = VkClientErrorCode.MISSING_REQUIRED_PARAMS;
      } else if (error.code === INVALID_ARGUMENT) {
        code = VkClientErrorCode.INVALID_PARAMS;
      }
    }
    const failure = error instanceof VkBridgeError ? error : VkBridgeError.client(code);
    const data = failure.toData();
    if (requestId !== undefined) {
      data.request_id = requestId;
    }
    return { type: eventName, data };
  }

  static mergeSupportedHandlers(current: string[], added: string[]): string[] {
    const set = new Set(current);
    added.forEach(item => set.add(item));
    return Array.from(set);
  }
}
