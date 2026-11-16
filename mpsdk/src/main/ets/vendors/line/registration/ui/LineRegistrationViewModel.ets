import { common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { LinePhoneRegistrationSession } from '../LinePhoneRegistrationSession';
import { LinePhoneRegistrationState } from '../LineRegistrationSessionTypes';
import { HostLifecycleMonitor } from '../../../../core/HostLifecycleMonitor';
import { LineRegistrationChallengeHost } from './LineRegistrationChallengeHost';
import { LineRegistrationWebProtocol } from './LineRegistrationWebProtocol';
import { LineCountryAgreement } from '../LineRegistrationTypes';
import { LineErrorCode } from '../../LineErrorCode';

export interface LineRegistrationCountryOption { value: string; label: string; }

@ObservedV2
export class LineRegistrationViewModel {
  @Trace state: LinePhoneRegistrationState = { stage: 'initializing', busy: true };
  @Trace phone: string = '';
  @Trace code: string = '';
  @Trace name: string = '';
  @Trace password: string = '';
  @Trace autoAdd: boolean = false;
  @Trace searchable: boolean = false;
  @Trace error: boolean = false;
  @Trace retryAfterChallenge: boolean = false;
  @Trace countries: LineRegistrationCountryOption[] = [];
  @Trace countryIndex: number = -1;
  dismissKeyboard?: () => boolean;
  private active: boolean = true;
  private readonly publicPage: LineRegistrationChallengeHost = new LineRegistrationChallengeHost();
  private session?: LinePhoneRegistrationSession;
  private context?: common.UIAbilityContext;

  bind(session: LinePhoneRegistrationSession, context: common.UIAbilityContext): void {
    this.session = session; this.context = context; this.active = true;
    this.update(session.getState());
    try {
      const locale = i18n.System.getSystemLocale();
      this.countries = i18n.System.getSystemCountries(i18n.System.getSystemLanguage()).filter((code: string): boolean => /^[A-Z]{2}$/.test(code))
        .map((code: string): LineRegistrationCountryOption => ({ value: code, label: i18n.System.getDisplayCountry(code, locale) }));
      this.countryIndex = this.countries.findIndex((country: LineRegistrationCountryOption): boolean => country.value === this.state.countryCode);
    } catch (_) { this.countries = []; this.error = true; }
  }
  update(state: LinePhoneRegistrationState): void {
    if (!this.active) { return; }
    if (state.stage !== this.state.stage) { this.clearSecrets(); }
    this.state = state;
    this.countryIndex = this.countries.findIndex((country: LineRegistrationCountryOption): boolean => country.value === state.countryCode);
  }
  refresh(): void { if (this.active && this.session) { this.update(this.session.getState()); } }
  errorMessage(): Resource {
    switch (this.state.errorCode) {
      case LineErrorCode.REGISTRATION_UNSUPPORTED:
        if (this.state.stage === 'countrySelection' || this.state.stage === 'phoneInput') {
          return $r('app.string.mp_line_registration_error_country');
        }
        return $r('app.string.mp_line_registration_error_unsupported');
      case LineErrorCode.REGISTRATION_RULE_UNSUPPORTED:
        return $r('app.string.mp_line_registration_error_unsupported');
      case LineErrorCode.REGISTRATION_APP_UPGRADE_REQUIRED:
        return $r('app.string.mp_line_registration_error_upgrade');
      case LineErrorCode.REGISTRATION_INVALID_CONTEXT:
      case LineErrorCode.REGISTRATION_NOT_FOUND:
      case LineErrorCode.REGISTRATION_INVALID_STATE:
        return $r('app.string.mp_line_registration_error_reset');
      case LineErrorCode.REGISTRATION_VERIFICATION_FAILED:
        return $r('app.string.mp_line_registration_error_verification');
      case LineErrorCode.REGISTRATION_RETRY_LATER:
      case LineErrorCode.RPC_RETRY_LATER:
        return $r('app.string.mp_line_registration_error_retry_later');
      case LineErrorCode.REGISTRATION_ILLEGAL_ARGUMENT:
      case LineErrorCode.REGISTRATION_PASSWORD_INVALID:
        return $r('app.string.mp_line_registration_error_input');
      case LineErrorCode.REGISTRATION_NOT_ALLOWED:
        return $r('app.string.mp_line_registration_error_not_allowed');
      case LineErrorCode.REGISTRATION_ACCOUNT_CONFLICT:
        return $r('app.string.mp_line_registration_error_account_conflict');
      case LineErrorCode.REGISTRATION_HUMAN_VERIFICATION_REQUIRED:
        return $r('app.string.mp_line_registration_challenge');
      case LineErrorCode.REGISTRATION_INCOMPLETE:
        return $r('app.string.mp_line_registration_pending');
      case LineErrorCode.REGISTRATION_CREATION_UNCERTAIN:
        return $r('app.string.mp_line_registration_uncertain');
      default:
        return $r('app.string.mp_line_registration_error');
    }
  }
  clearSecrets(): void { this.code = ''; this.password = ''; }
  dispose(): void { this.active = false; this.clearSecrets(); this.phone = ''; this.name = ''; this.publicPage.cancel(); this.session = undefined; this.context = undefined; }
  async perform(action: (session: LinePhoneRegistrationSession) => Promise<void>): Promise<void> {
    const session = this.session;
    const context = this.context;
    if (!this.active || !session || !context) { return; }
    this.error = false; this.retryAfterChallenge = false;
    try { HostLifecycleMonitor.assertForeground(context); await action(session); }
    catch (_) { if (this.active) { this.error = true; } }
    if (this.active) { this.refresh(); }
  }
  selectCountry(index: number): void {
    const country = this.countries[index];
    if (country) { this.perform((session): Promise<void> => session.selectCountry(country.value)); }
  }
  submitCode(): void { const code = this.code; this.code = ''; this.perform((session): Promise<void> => session.verifyCode(code)); }
  submitPassword(): void { const password = this.password; this.password = ''; this.perform((session): Promise<void> => session.createAccount(password)); }
  challenge(): void {
    const context = this.context;
    if (!context) { return; }
    this.perform(async (session): Promise<void> => {
      await session.presentChallenge(context);
      if (this.active && session.getState().stage !== 'challengeRequired') { this.retryAfterChallenge = true; }
    });
  }
  agreement(): void { const context = this.context; if (context) { this.perform((session): Promise<void> => session.presentAgreement(context)); } }
  async publicPolicy(terms: boolean): Promise<void> {
    if (!this.context || !this.active) { return; }
    try {
      HostLifecycleMonitor.assertForeground(this.context);
      const locale = LineRegistrationWebProtocol.publicLocale(i18n.System.getSystemLocale());
      const address = terms ? LineRegistrationWebProtocol.publicTerms(locale) :
        (this.state.countryCode === 'KR' ? 'https://line.me/ko/terms/policy/' : LineRegistrationWebProtocol.publicPolicy(LineCountryAgreement.GDPR, locale));
      await this.publicPage.show(this.context, address, [], 'public');
    } catch (_) { if (this.active) { this.error = true; } }
  }
}
