import { url } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineErrorCode } from '../LineErrorCode';
import { LINE_CONSENT_SCHEME, LineConsentCommand } from '../scheme/LineSchemeConstants';

const CONSENT_ORIGIN: string = 'https://access.line.me';

/** 授权策略的内部处理结果，与 URI 中的命令名区分。 */
export enum LineConsentDecision {
  ALLOW,
  DENY,
  LOAD,
  BLOCK
}

/** APK w98/a 的授权回调；未知协议及外站不进入携带账号身份的 WebView。 */
export class LineConsentProtocol {
  static validateUrl(address: string): string {
    try {
      const parsed = new url.URL(address);
      if (parsed.origin === CONSENT_ORIGIN && !parsed.username && !parsed.password) {
        return address;
      }
    } catch (_) { /* 地址错误统一映射，不回传包含一次性参数的 URL。 */
    }
    throw new MiniAppError(LineErrorCode.CONSENT_INVALID, 'LINE 授权页面地址无效');
  }

  static navigate(address: string, mainFrame: boolean, currentUrl: string): LineConsentDecision {
    try {
      const parsed = new url.URL(address);
      if (parsed.protocol === LINE_CONSENT_SCHEME + ':') {
        if (!mainFrame || parsed.username || parsed.password || parsed.port) {
          return LineConsentDecision.BLOCK;
        }
        LineConsentProtocol.validateUrl(currentUrl);
        if (parsed.hostname === LineConsentCommand.ALLOW || parsed.hostname === LineConsentCommand.RETRY) {
          return LineConsentDecision.ALLOW;
        }
        if (parsed.hostname === LineConsentCommand.DISALLOW) {
          return LineConsentDecision.DENY;
        }
        return LineConsentDecision.BLOCK;
      }
      LineConsentProtocol.validateUrl(address);
      return LineConsentDecision.LOAD;
    } catch (_) {
      return LineConsentDecision.BLOCK;
    }
  }
}
