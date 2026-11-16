/** WebView 资源请求处理模块内部稳定错误码；不依赖具体页面、厂商或资源请求。 */
export class WebRequestErrorCode {
  /** 处理器 id 格式或唯一性不符合约定。 */
  static readonly INVALID_REGISTRATION: string = 'WEB_REQUEST_INVALID_REGISTRATION';
  /** 同步处理器抛出异常，当前请求阻止。 */
  static readonly HANDLER_FAILED: string = 'WEB_REQUEST_HANDLER_FAILED';
  /** reset 钩子失败；继续清理其余处理器。 */
  static readonly RESET_FAILED: string = 'WEB_REQUEST_RESET_FAILED';
  /** dispose 钩子失败；继续释放其余处理器。 */
  static readonly DISPOSE_FAILED: string = 'WEB_REQUEST_DISPOSE_FAILED';
}
