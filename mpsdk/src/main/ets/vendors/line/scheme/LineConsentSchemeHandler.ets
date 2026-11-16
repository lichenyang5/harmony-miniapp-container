import { WebSchemeDecision, WebSchemeHandler, WebSchemeRequest } from '../../../web/scheme/WebSchemeTypes';
import { LineConsentDecision, LineConsentProtocol } from '../consent/LineConsentProtocol';
import { LINE_CONSENT_SCHEME } from './LineSchemeConstants';

/** 独立授权 WebView 的回调协议；页面加载白名单仍由该 WebView 自行检查。 */
export class LineConsentSchemeHandler implements WebSchemeHandler<WebSchemeRequest> {
  readonly id: string = 'line.consent';
  private active: boolean = true;
  private readonly currentUrl: () => string;
  private readonly complete: (allowed: boolean) => void;

  constructor(currentUrl: () => string, complete: (allowed: boolean) => void) {
    this.currentUrl = currentUrl;
    this.complete = complete;
  }

  supports(request: WebSchemeRequest): boolean {
    return request.url.toLowerCase().startsWith(LINE_CONSENT_SCHEME + ':');
  }

  handle(request: WebSchemeRequest): WebSchemeDecision {
    if (!this.active) {
      return WebSchemeDecision.BLOCK;
    }
    const action = LineConsentProtocol.navigate(request.url, request.isMainFrame, this.currentUrl());
    if (action !== LineConsentDecision.ALLOW && action !== LineConsentDecision.DENY) {
      return WebSchemeDecision.BLOCK;
    }
    // 先失效再通知，避免完成回调重入或弹层尚未消失时重复完成授权。
    this.active = false;
    this.complete(action === LineConsentDecision.ALLOW);
    return WebSchemeDecision.CONSUME;
  }

  dispose(): void {
    this.active = false;
  }
}
