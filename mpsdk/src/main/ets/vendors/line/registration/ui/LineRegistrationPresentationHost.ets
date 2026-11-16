import { common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { webview } from '@kit.ArkWeb';
import { LineRegistrationPresentation, LineRegistrationAgreementContext, LineRegistrationAgreementDecision } from '../LineRegistrationSessionTypes';
import { LineRegistrationWebAuthDetails, LineCountryAgreement } from '../LineRegistrationTypes';
import { LineRegistrationChallengeHost } from './LineRegistrationChallengeHost';
import { LineRegistrationWebProtocol, RegistrationWebResult } from './LineRegistrationWebProtocol';
import { MiniAppError } from '../../../../core/MiniAppError';
import { LineErrorCode } from '../../LineErrorCode';

/** Private per-session port; pending account headers never enter public UI state. */
export class LineRegistrationPresentationHost implements LineRegistrationPresentation {
  private readonly host: LineRegistrationChallengeHost = new LineRegistrationChallengeHost();
  private generation: number = 0;
  async presentChallenge(context: common.UIAbilityContext, details: LineRegistrationWebAuthDetails): Promise<boolean> {
    const headers: webview.WebHeader[] = [{ headerKey: 'Authorization', headerValue: details.token ?? '' }];
    return await this.host.show(context, details.baseUrl ?? '', headers, 'challenge') === RegistrationWebResult.ACCEPTED;
  }
  async presentAgreement(context: common.UIAbilityContext, agreements: number[],
    accountContext: () => Promise<LineRegistrationAgreementContext>,
    countryPolicy?: LineCountryAgreement): Promise<LineRegistrationAgreementDecision | undefined> {
    const generation = this.generation;
    const locale = i18n.System.getSystemLocale();
    if (agreements.length > 0) {
      const agreement = agreements[0];
      // Validate the mapping before requesting any credential-bearing context.
      if (agreement !== 47 && agreement !== 50) { throw new MiniAppError(LineErrorCode.REGISTRATION_UNSUPPORTED, 'Unsupported LINE agreement'); }
      const account = await accountContext();
      if (generation !== this.generation) { throw new MiniAppError(LineErrorCode.REGISTRATION_CANCELLED, 'LINE registration closed'); }
      const headers: webview.WebHeader[] = [];
      Object.keys(account.headers).forEach((key: string): void => { headers.push({ headerKey: key, headerValue: account.headers[key] }); });
      await this.host.show(context, LineRegistrationWebProtocol.pending(account.endpoint, agreement, locale.split('-')[0]), headers, 'pending');
      // Both acceptance and refusal require actual getPendingAgreements in the finalizer.
      return undefined;
    }
    if (!countryPolicy) { return undefined; }
    const result = await this.host.show(context,
      LineRegistrationWebProtocol.publicPolicy(countryPolicy, LineRegistrationWebProtocol.publicLocale(locale)), [], 'country');
    if (result === RegistrationWebResult.CLOSED) { return undefined; }
    return { policy: countryPolicy, timestampMs: (result === RegistrationWebResult.ACCEPTED ? 1 : -1) * Date.now() };
  }
  cancel(): void { this.generation++; this.host.cancel(); }
}
