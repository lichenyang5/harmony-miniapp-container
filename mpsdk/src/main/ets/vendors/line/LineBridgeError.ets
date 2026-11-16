import { LineBridgeErrorCode, LineErrorCode } from './LineErrorCode';
import { MiniAppError } from '../../core/MiniAppError';

/** LINE 网页错误载荷；不包含 SDK 异常、堆栈或原始原因。 */
export interface LineBridgeErrorData {
  code: string;
  description: string;
}

/** 已确认的桥层错误；业务方法的错误映射随 Handler 单独实现。 */
export class LineBridgeError extends MiniAppError {
  private readonly data: LineBridgeErrorData;

  private constructor(code: string, description: string, originalCause?: Object | null) {
    super(LineErrorCode.BRIDGE_ERROR, description, originalCause);
    this.name = 'LineBridgeError';
    this.data = { code, description };
  }

  static noAuthority(): LineBridgeError {
    // 保留 APK 原文，包括 mached 拼写。
    return new LineBridgeError(LineBridgeErrorCode.NO_AUTHORITY, 'A featureToken is not mached.');
  }

  static permissionDenied(type: string): LineBridgeError {
    return new LineBridgeError(LineBridgeErrorCode.PERMISSION_DENIED, `"${type}" is not allowed in your app.`);
  }

  static invalidMessage(type: string): LineBridgeError {
    return new LineBridgeError(LineBridgeErrorCode.INVALID_MESSAGE, `"${type}" is invalid message.`);
  }

  static invalidArgument(originalCause?: Object | null): LineBridgeError {
    return new LineBridgeError(LineBridgeErrorCode.INVALID_ARGUMENT, 'Invalid argument', originalCause);
  }

  static forbidden(description: string): LineBridgeError {
    return new LineBridgeError(LineBridgeErrorCode.FORBIDDEN, description);
  }

  /** SDK 防御性兜底，不能据此宣称 APK 统一捕获所有异常。 */
  static internal(originalCause?: Object | null): LineBridgeError {
    return new LineBridgeError(LineBridgeErrorCode.INTERNAL_ERROR, 'Internal error', originalCause);
  }

  static unknown(description: string, originalCause?: Object | null): LineBridgeError {
    return new LineBridgeError(LineBridgeErrorCode.UNKNOWN, description, originalCause);
  }

  toData(): LineBridgeErrorData {
    return { code: this.data.code, description: this.data.description };
  }
}
