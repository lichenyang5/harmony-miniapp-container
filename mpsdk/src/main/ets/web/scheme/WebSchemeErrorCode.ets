/** WebView 协议处理模块内部稳定错误码；不依赖具体页面、厂商或协议。 */
export class WebSchemeErrorCode {
  /** 注册元数据、同步方法或唯一 id 不符合约定。 */
  static readonly INVALID_REGISTRATION: string = 'WEB_SCHEME_INVALID_REGISTRATION';
  /** 同步处理器抛出异常，当前请求阻止。 */
  static readonly HANDLER_FAILED: string = 'WEB_SCHEME_HANDLER_FAILED';
  /** 返回值不是约定的同步协议处理结果，当前请求阻止。 */
  static readonly INVALID_DECISION: string = 'WEB_SCHEME_INVALID_DECISION';
  /** reset 钩子失败；继续清理其余处理器。 */
  static readonly RESET_FAILED: string = 'WEB_SCHEME_RESET_FAILED';
  /** dispose 钩子失败；继续释放其余处理器。 */
  static readonly DISPOSE_FAILED: string = 'WEB_SCHEME_DISPOSE_FAILED';
}
