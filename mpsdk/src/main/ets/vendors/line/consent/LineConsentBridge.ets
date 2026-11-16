import { LineConsentProtocol } from './LineConsentProtocol';
import { SdkLogger } from '../../../logging/SdkLogger';
import { LineErrorCode } from '../LineErrorCode';

export const LINE_CONSENT_BRIDGE_NAME: string = 'line';

/** 官方成功页的脚本回调；不暴露账号接口或凭据，不能由失效页面完成授权。 */
export class LineConsentBridge {
  private active: boolean = true;
  private readonly currentUrl: () => string;
  private readonly allowed: () => void;

  constructor(currentUrl: () => string, allowed: () => void) {
    this.currentUrl = currentUrl;
    this.allowed = allowed;
  }

  onUserAllowed(): void {
    if (!this.active) {
      return;
    }
    try {
      LineConsentProtocol.validateUrl(this.currentUrl());
    } catch (_) {
      SdkLogger.warn('LineConsent', 'callbackBlocked', { code: LineErrorCode.CONSENT_INVALID });
      return;
    }
    this.active = false;
    SdkLogger.info('LineConsent', 'callbackReceived', { code: 'JS_ALLOWED' });
    this.allowed();
  }

  dispose(): void {
    this.active = false;
  }
}
