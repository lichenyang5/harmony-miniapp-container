import { LineBridgeError, LineBridgeErrorData } from './LineBridgeError';

export interface LineBridgeRequest {
  type: string;
  featureToken: string;
  callbackId: string;
  params: object;
}

interface LineBridgeEvent<TData extends object = object> {
  type: string;
  callbackId?: string;
  data?: TData;
  error?: LineBridgeErrorData;
}

/** 仅负责 LINE 线协议；不判断来源、不激活桥，也不执行网页脚本。 */
export class LineBridgeProtocol {
  static parseRequest(type: string, featureToken: string, callbackId: string,
    paramsJson: string): LineBridgeRequest | undefined {
    // ArkTS 签名不代替网页输入校验；无合法关联字段时不编造失败回包。
    if (typeof type !== 'string' || typeof featureToken !== 'string' ||
      typeof callbackId !== 'string' || typeof paramsJson !== 'string') {
      return undefined;
    }
    return {
      type,
      featureToken,
      callbackId,
      params: LineBridgeProtocol.parseParams(paramsJson)
    };
  }

  /** 返回事件 JSON；序列化异常交给分发器统一转失败回包，并丢弃成功后的动作。 */
  static serializeSuccess<TData extends object = object>(type: string,
    callbackId: string | undefined, data?: TData): string {
    const event: LineBridgeEvent<TData> = { type, callbackId, data };
    return JSON.stringify(event);
  }

  static serializeFailure(type: string, callbackId: string | undefined, error: LineBridgeError): string {
    const event: LineBridgeEvent = { type, callbackId, error: error.toData() };
    return JSON.stringify(event);
  }

  private static parseParams(paramsJson: string): object {
    const emptyParams: Record<string, Object> = {};
    if (paramsJson === 'undefined') {
      return emptyParams;
    }
    try {
      const parsed = JSON.parse(paramsJson) as Object;
      // JSONObject 入口只接收对象；数组、null 和标量按解析失败处理。
      if (parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed;
      }
    } catch (_) {
      // 原版解析失败转空对象，具体字段错误由后续 Handler 判断。
    }
    return emptyParams;
  }
}
