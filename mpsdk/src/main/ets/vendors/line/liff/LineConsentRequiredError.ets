import { MiniAppError } from '../../../core/MiniAppError';
import { LineErrorCode, LineServiceErrorCode } from '../LineErrorCode';

/**
 * 发行服务返回的授权要求，仅供原生授权流程消费，不导出为宿主公共 API。
 * consentUrl 可能包含一次性参数；不写入日志、错误文案或持久化存储。
 * URL 来自协议响应，不代表允许任意导航，展示前仍须按授权页面规则校验。
 */
export class LineConsentRequiredError extends MiniAppError {
  readonly channelId?: string;
  readonly consentUrl: string;

  constructor(channelId: string | undefined, consentUrl: string) {
    super(LineErrorCode.liffService(LineServiceErrorCode.LIFF_CONSENT_REQUIRED), 'LINE 小程序需要用户同意授权');
    this.channelId = channelId;
    this.consentUrl = consentUrl;
  }
}
