import { url } from '@kit.ArkTS';
import { MiniAppError } from '../../../../core/MiniAppError';
import { LineErrorCode } from '../../LineErrorCode';
import { LINE_CONSENT_SCHEME } from '../../scheme/LineSchemeConstants';
import { LineCountryAgreement } from '../LineRegistrationTypes';

export enum RegistrationWebResult { CLOSED, ACCEPTED, DECLINED }
export enum RegistrationWebDecision { LOAD, BLOCK, ACCEPTED, DECLINED, FATAL }
export type RegistrationWebKind = 'challenge' | 'pending' | 'country' | 'public';

/** Callback acceptance is local window completion, never service success. */
export class LineRegistrationWebProtocol {
  private document: string = '';
  private active: boolean = true;
  private readonly origin: string;
  readonly address: string;
  readonly kind: RegistrationWebKind;
  constructor(address: string, kind: RegistrationWebKind) {
    this.address = address; this.kind = kind;
    this.origin = LineRegistrationWebProtocol.https(address).origin;
  }
  static https(address: string): url.URL {
    try {
      const parsed = new url.URL(address);
      if (parsed.protocol === 'https:' && !parsed.username && !parsed.password && !parsed.port) { return parsed; }
    } catch (_) { /* Never return private URL in errors. */ }
    throw new MiniAppError(LineErrorCode.REGISTRATION_UNSUPPORTED, 'Unsupported LINE registration page');
  }
  begin(address: string): void {
    this.document = this.allowed(address) ? address : '';
  }
  stop(): void { this.active = false; this.document = ''; }
  allowed(address: string): boolean {
    try { return LineRegistrationWebProtocol.https(address).origin === this.origin; } catch (_) { return false; }
  }
  navigate(address: string, mainFrame: boolean, currentUrl: string): RegistrationWebDecision {
    if (!this.active) { return RegistrationWebDecision.BLOCK; }
    if (address.startsWith(LINE_CONSENT_SCHEME + ':')) {
      if (!mainFrame || !this.document || currentUrl !== this.document || !this.allowed(currentUrl) || (this.kind === 'country' || this.kind === 'public')) { return RegistrationWebDecision.BLOCK; }
      if (address === LINE_CONSENT_SCHEME + '://accepted' || (this.kind === 'pending' && address === LINE_CONSENT_SCHEME + '://ok')) { return RegistrationWebDecision.ACCEPTED; }
      if (this.kind === 'pending' && address === LINE_CONSENT_SCHEME + '://declined') { return RegistrationWebDecision.DECLINED; }
      if (this.kind === 'challenge' && (address === LINE_CONSENT_SCHEME + '://fatalError' || address === LINE_CONSENT_SCHEME + '://startOver')) { return RegistrationWebDecision.FATAL; }
      return RegistrationWebDecision.BLOCK;
    }
    // Captcha providers may embed cross-origin HTTPS frames. They never receive native
    // headers or callback authority; only the currently owned top document can finish.
    if (!mainFrame && this.document && currentUrl === this.document && this.allowed(currentUrl)) {
      if (address === 'about:blank') { return RegistrationWebDecision.LOAD; }
      try { LineRegistrationWebProtocol.https(address); return RegistrationWebDecision.LOAD; } catch (_) {}
    }
    return this.allowed(address) ? RegistrationWebDecision.LOAD : RegistrationWebDecision.BLOCK;
  }
  static pending(endpoint: string, agreement: number, language: string): string {
    // APK gp8.bh + bm8.g: only these two values share the verified pending route.
    if (agreement !== 47 && agreement !== 50) { throw new MiniAppError(LineErrorCode.REGISTRATION_UNSUPPORTED, 'Unsupported LINE agreement'); }
    return LineRegistrationWebProtocol.https(endpoint).origin + '/view/privacy/agreement/pending?agreement=' + agreement.toString() + '&language=' + encodeURIComponent(language);
  }
  static publicPolicy(policy: LineCountryAgreement, locale: string): string {
    return policy === LineCountryAgreement.ICNA ? 'https://terms.line.me/Privacy_Notice_KR_Consent/sp?lang=' + encodeURIComponent(locale) :
      'https://terms.line.me/line_rules/sp?lang=' + encodeURIComponent(locale);
  }
  static publicTerms(locale: string): string { return 'https://terms.line.me/line_terms/sp?lang=' + encodeURIComponent(locale); }
  static publicLocale(locale: string): string {
    const parts = locale.replace(/_/g, '-').split('-');
    const region = parts.find((part: string, index: number): boolean => index > 0 && /^[A-Z]{2}$/.test(part));
    if (region === 'ID') { return 'id'; }
    if (region === 'TW') { return 'zh-Hant'; }
    return parts[0] || 'en';
  }
}
