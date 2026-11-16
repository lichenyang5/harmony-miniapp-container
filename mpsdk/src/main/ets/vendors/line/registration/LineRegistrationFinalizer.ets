import { MiniAppError } from '../../../core/MiniAppError';
import { LineErrorCode } from '../LineErrorCode';
import { LineCountryAgreement, LineRegistrationPrivacy, LineRegistrationSettings } from './LineRegistrationTypes';
import { LineRegistrationCheckpoint, LineRegistrationSessionHooks, LineRegistrationStage,
  LineRegistrationAgreementDecision } from './LineRegistrationSessionTypes';

/** Resumable account setup. Every network await is followed by identity/UI validation. */
export class LineRegistrationFinalizer {
  private readonly checkpoint: LineRegistrationCheckpoint;
  private readonly hooks: LineRegistrationSessionHooks;
  private readonly assertActive: () => void;
  private pending: number[] = [];

  constructor(checkpoint: LineRegistrationCheckpoint, hooks: LineRegistrationSessionHooks, assertActive: () => void) {
    this.checkpoint = checkpoint;
    this.hooks = hooks;
    this.assertActive = assertActive;
  }

  agreements(): number[] { return this.pending.slice(); }

  choosePrivacy(privacy: LineRegistrationPrivacy): void {
    if (!privacy || typeof privacy.privacySyncContacts !== 'boolean' ||
      typeof privacy.privacySearchByPhoneNumber !== 'boolean' ||
      privacy.privacySearchByUserid !== undefined && typeof privacy.privacySearchByUserid !== 'boolean') {
      throw new MiniAppError(LineErrorCode.REGISTRATION_ILLEGAL_ARGUMENT, 'Invalid LINE privacy choice');
    }
    this.checkpoint.privacy = { privacySyncContacts: privacy.privacySyncContacts,
      privacySearchByPhoneNumber: privacy.privacySearchByPhoneNumber, privacySearchByUserid: privacy.privacySearchByUserid };
    this.checkpoint.privacyUpdated = false;
    this.save();
  }

  skipAge(): void {
    if (this.checkpoint.countryCode !== 'JP') {
      throw new MiniAppError(LineErrorCode.REGISTRATION_INVALID_STATE, 'LINE age verification is unavailable');
    }
    this.checkpoint.ageVerification = 'SKIPPED';
    this.save();
  }

  recordAgreement(decision?: LineRegistrationAgreementDecision): void {
    if (!decision) { return; }
    if (decision.policy !== this.countryPolicy() || !Number.isSafeInteger(decision.timestampMs) || decision.timestampMs === 0) {
      throw new MiniAppError(LineErrorCode.REGISTRATION_UNSUPPORTED, 'LINE country agreement cannot be verified');
    }
    this.checkpoint.countryDecision = { policy: decision.policy, timestampMs: decision.timestampMs };
    this.checkpoint.countryUpdated = false;
    this.save();
  }

  async resume(): Promise<LineRegistrationStage> {
    this.assertActive();
    const talk = this.hooks.talk();
    const checkpoint = this.checkpoint;
    if (!checkpoint.nameUpdated) {
      await this.call(() => talk.updateName(checkpoint.displayName));
      this.assertActive(); checkpoint.nameUpdated = true; this.save();
    }
    const profile = await this.call(() => talk.getProfile());
    this.assertActive();
    if (!profile.mid || !profile.regionCode || !/^[A-Z]{2}$/.test(profile.regionCode)) {
      throw new MiniAppError(LineErrorCode.REGISTRATION_PROTOCOL_ERROR, 'Incomplete LINE profile');
    }
    this.hooks.assertProfile(profile.mid);
    const region: string = profile.regionCode;
    checkpoint.profileRegion = region;
    this.save();
    const agreements = await this.call(() => talk.getPendingAgreements());
    this.assertActive();
    if (!agreements.pendingAgreements || agreements.pendingAgreements.some((value: number): boolean => !Number.isInteger(value))) {
      throw new MiniAppError(LineErrorCode.REGISTRATION_PROTOCOL_ERROR, 'Incomplete LINE policy status');
    }
    this.pending = agreements.pendingAgreements.slice();
    if (!checkpoint.configurationsLoaded) {
      try {
        await this.call(() => talk.getConfigurations({ revision: 0, regionOfUsim: '', regionOfTelephone: region,
          regionOfLocale: checkpoint.countryCode, carrier: '' }));
      } catch (error) {
        this.assertActive();
        // APK k35.g0.j tolerates Thrift failures only in this configuration phase.
        // Identity, transport, protocol corruption and refresh errors remain blocking.
        if (!(error instanceof MiniAppError) ||
          (error.code !== LineErrorCode.REGISTRATION_APPLICATION_ERROR && error.code !== LineErrorCode.REGISTRATION_TALK_REJECTED)) {
          throw MiniAppError.from(error as Object, LineErrorCode.REGISTRATION_FAILED, 'LINE finalization failed');
        }
      }
      this.assertActive(); checkpoint.configurationsLoaded = true; this.save();
    }
    if (!checkpoint.privacy || typeof checkpoint.privacy !== 'object' || Array.isArray(checkpoint.privacy) ||
      typeof checkpoint.privacy.privacySyncContacts !== 'boolean' ||
      typeof checkpoint.privacy.privacySearchByPhoneNumber !== 'boolean' ||
      checkpoint.privacy.privacySearchByUserid !== undefined && typeof checkpoint.privacy.privacySearchByUserid !== 'boolean') {
      return 'privacySettings';
    }
    if (checkpoint.countryCode === 'JP' && checkpoint.ageVerification !== 'SKIPPED') { return 'ageVerification'; }
    if (this.pending.length > 0) { return 'agreementRequired'; }
    await this.call(() => talk.getSettings());
    this.assertActive();
    const policy = this.countryPolicy();
    if (policy) {
      const decision = checkpoint.countryDecision;
      if (!decision || typeof decision !== 'object' || Array.isArray(decision) || decision.policy !== policy ||
        !Number.isSafeInteger(decision.timestampMs) || decision.timestampMs === 0) { return 'agreementRequired'; }
    }
    if (policy && !checkpoint.countryUpdated) {
      const decision = checkpoint.countryDecision!;
      await this.call(() => talk.updateCountryAgreement(policy, decision.timestampMs));
      this.assertActive();
      const settings = await this.call(() => talk.getSettings()); this.assertActive();
      if (this.agreementTimestamp(settings, policy) !== decision.timestampMs) {
        throw new MiniAppError(LineErrorCode.REGISTRATION_INCOMPLETE, 'LINE country agreement is not confirmed');
      }
      checkpoint.countryUpdated = true; this.save();
    }
    if (!checkpoint.privacyUpdated) {
      await this.call(() => talk.updatePrivacy(checkpoint.privacy!));
      this.assertActive();
      const settings = await this.call(() => talk.getSettings()); this.assertActive();
      if (settings.privacySyncContacts !== checkpoint.privacy.privacySyncContacts ||
        settings.privacySearchByPhoneNumber !== checkpoint.privacy.privacySearchByPhoneNumber ||
        checkpoint.privacy.privacySearchByUserid !== undefined &&
        settings.privacySearchByUserid !== checkpoint.privacy.privacySearchByUserid) {
        throw new MiniAppError(LineErrorCode.REGISTRATION_INCOMPLETE, 'LINE privacy settings are not confirmed');
      }
      checkpoint.privacyUpdated = true; this.save();
    }
    // Server may introduce or retain a required agreement after a decision/update.
    const finalAgreements = await this.call(() => talk.getPendingAgreements());
    this.assertActive();
    if (!finalAgreements.pendingAgreements) {
      throw new MiniAppError(LineErrorCode.REGISTRATION_PROTOCOL_ERROR, 'Incomplete LINE policy status');
    }
    this.pending = finalAgreements.pendingAgreements.slice();
    return this.pending.length > 0 ? 'agreementRequired' : 'ready';
  }

  countryPolicy(): LineCountryAgreement | undefined {
    const country = this.checkpoint.profileRegion;
    if (country === 'TH') { return LineCountryAgreement.TH_PDPA; }
    if (country === 'KR') { return LineCountryAgreement.ICNA; }
    if (country === 'ID') { return LineCountryAgreement.ID_PDP; }
    if (country && this.checkpoint.countrySetOfEEA.indexOf(country) >= 0) { return LineCountryAgreement.GDPR; }
    return undefined;
  }

  private save(): void { this.assertActive(); this.hooks.save(this.checkpoint); }

  private agreementTimestamp(settings: LineRegistrationSettings, policy: LineCountryAgreement): number | undefined {
    switch (policy) {
      case LineCountryAgreement.GDPR: return settings.agreementGdpr;
      case LineCountryAgreement.ICNA: return settings.agreementIcna;
      case LineCountryAgreement.TH_PDPA: return settings.agreementPdpa;
      case LineCountryAgreement.ID_PDP: return settings.agreementPdp;
    }
  }

  private async call<T>(operation: () => Promise<T>): Promise<T> {
    this.assertActive();
    try { return await operation(); }
    catch (error) {
      this.assertActive();
      if (!(error instanceof MiniAppError) || error.code !== LineErrorCode.REGISTRATION_TOKEN_REFRESH_REQUIRED) { throw MiniAppError.from(error as Object, LineErrorCode.REGISTRATION_FAILED, 'LINE finalization failed'); }
      await this.hooks.refreshPending(); this.assertActive();
      return operation();
    }
  }
}
