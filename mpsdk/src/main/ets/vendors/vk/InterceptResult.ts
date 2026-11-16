/** 最终桥接拦截结果，data 始终为待转发的完整消息。 */
export class InterceptResult {
  intercept: boolean;
  data: object | undefined;
  timeout: number | undefined;

  constructor(intercept: boolean, data?: object, timeout?: number) {
    this.intercept = intercept;
    this.data = data;
    this.timeout = timeout;
  }

  static intercept(timeout?: number): InterceptResult {
    return new InterceptResult(true, undefined, timeout);
  }

  static hook(data?: object): InterceptResult {
    return new InterceptResult(false, data);
  }

  static pass(): InterceptResult {
    return new InterceptResult(false);
  }
}
