/** SDK 统一异常；主动错误使用稳定 code，平台异常在边界转换并保留原始原因。 */
export class MiniAppError extends Error {
  /** 稳定的错误标识，可用于日志或错误提示分流。 */
  readonly code: string;
  /** 原始异常，仅用于原生诊断，不应直接序列化或回传给小程序网页。 */
  readonly originalCause: Object | null | undefined;

  /**
   * 创建容器错误。
   * @param code 错误标识，例如 VENDOR_NOT_READY。
   * @param message 可读说明，通过 Error.message 获取。
   * @param originalCause 可选的底层异常或拒绝原因，不参与错误码判断。
   */
  constructor(code: string, message: string, originalCause?: Object | null) {
    super(message);
    this.name = 'MiniAppError';
    this.code = code;
    this.originalCause = originalCause;
  }

  /**
   * 在异常边界统一错误类型，不根据消息文本或外部对象的 code 判断 SDK 错误。
   * @param error 捕获的异常或拒绝原因，允许为空或非 Error 值。
   * @param fallbackCode 非 SDK 异常的分类码。
   * @param fallbackMessage 当前操作的可读失败说明。
   * @returns 已有 MiniAppError 原样返回；其他值包装一次并保留原始原因。
   */
  static from(error: Object | null | undefined, fallbackCode: string, fallbackMessage: string): MiniAppError {
    if (error instanceof MiniAppError) {
      return error;
    }
    return new MiniAppError(fallbackCode, fallbackMessage, error);
  }
}
