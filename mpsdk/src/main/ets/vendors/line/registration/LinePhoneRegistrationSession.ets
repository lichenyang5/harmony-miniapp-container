import { common } from '@kit.AbilityKit';
import { process } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineErrorCode } from '../LineErrorCode';
import { LineRegistrationPasswordCrypto } from './LineRegistrationCrypto';
import { LineRegistrationError } from './LineRegistrationError';
import { LineRegistrationFinalizer } from './LineRegistrationFinalizer';
import { LineRegistrationDiagnostics } from './LineRegistrationDiagnostics';
import { LineRegistrationMethod, LinePhoneVerificationMethod, LineRegistrationPrivacy,
  LineRegistrationVerifyResponse, LineRegistrationWebAuthDetails, LineRegistrationPhone, LineRegistrationPhoneRequest } from './LineRegistrationTypes';
import { LinePhoneRegistrationState, LineRegistrationStage, LineRegistrationCheckpoint,
  LineRegistrationOperations, LineRegistrationPresentation, LineRegistrationSessionHooks, LineRegistrationAgreementContext } from './LineRegistrationSessionTypes';

const RESEND_DELAY_MS: number = 60000;

/** A single low-level interaction owner. Creation settlement outlives UI cancellation. */
export class LinePhoneRegistrationSession {
  readonly result: Promise<void>;
  private resolveResult: () => void = (): void => {};
  private rejectResult: (error: MiniAppError) => void = (_error: MiniAppError): void => {};
  private readonly client: LineRegistrationOperations;
  private readonly crypto: LineRegistrationPasswordCrypto;
  private readonly hooks: LineRegistrationSessionHooks;
  private readonly observer: (state: LinePhoneRegistrationState) => void;
  private readonly presentation?: LineRegistrationPresentation;
  private readonly now: () => number;
  private readonly diagnostics: LineRegistrationDiagnostics;
  private state: LinePhoneRegistrationState = { stage: 'initializing' };
  private active: boolean = true;
  // Reserve initialization before the constructor's microtask starts.
  private busy: boolean = true;
  private createInFlight: boolean = false;
  private released: boolean = false;
  private authSessionId: string = '';
  private normalizedPhoneNumber: string = '';
  private displayName: string = '';
  private countrySetOfEEA: string[] = [];
  private resendAt: number = 0;
  private selectedMethod?: LinePhoneVerificationMethod;
  private challenge?: LineRegistrationWebAuthDetails;
  private challengeReturn: LineRegistrationStage = 'phoneInput';
  private finalizer?: LineRegistrationFinalizer;

  constructor(client: LineRegistrationOperations, crypto: LineRegistrationPasswordCrypto,
    hooks: LineRegistrationSessionHooks, observer: (state: LinePhoneRegistrationState) => void,
    // process.uptime() is monotonic seconds and supports atomic services from API 11.
    presentation?: LineRegistrationPresentation, now: () => number = (): number => process.uptime() * 1000,
    diagnostics: LineRegistrationDiagnostics = new LineRegistrationDiagnostics()) {
    this.client = client; this.crypto = crypto; this.hooks = hooks; this.observer = observer;
    this.presentation = presentation; this.now = now;
    this.diagnostics = diagnostics;
    this.result = new Promise<void>((resolve, reject): void => { this.resolveResult = resolve; this.rejectResult = reject; });
    // Ensure caller obtains the session before any observer/restore work executes.
    Promise.resolve().then((): Promise<void> => this.initialize());
  }

  getState(): LinePhoneRegistrationState {
    return { stage: this.state.stage, countryCode: this.state.countryCode,
      availableMethods: this.state.availableMethods?.slice(), prettifiedPhoneNumber: this.state.prettifiedPhoneNumber,
      resendRemainingMs: Math.max(0, this.resendAt - this.now()), destinationPhoneNumber: this.state.destinationPhoneNumber,
      pinCodeMessage: this.state.pinCodeMessage, errorCode: this.state.errorCode, busy: this.busy };
  }

  /** Explicit retry after an initialization challenge; the existing PAIS session is retained. */
  async retryInitialization(): Promise<void> {
    this.assertActive();
    if (this.busy || this.state.stage !== 'initializing') {
      throw new MiniAppError(LineErrorCode.REGISTRATION_INVALID_STATE, 'LINE initialization retry is unavailable');
    }
    await this.initialize(true);
  }

  selectCountry(countryCode: string): Promise<void> {
    return this.run('selectCountry', ['countrySelection', 'phoneInput', 'verification'], async (): Promise<void> => {
      if (!/^[A-Z]{2}$/.test(countryCode)) { throw this.invalidArgument(); }
      if (!await this.allowCountry(countryCode)) { throw this.unsupported(); }
      this.normalizedPhoneNumber = ''; this.selectedMethod = undefined; this.resendAt = 0;
      this.state.availableMethods = undefined; this.state.prettifiedPhoneNumber = undefined;
      this.clearPullInstructions();
      this.setStage('phoneInput');
    });
  }

  submitPhoneNumber(phoneNumber: string): Promise<void> {
    return this.run('submitPhoneNumber', ['phoneInput', 'verification'], async (): Promise<void> => {
      if (typeof phoneNumber !== 'string' || !phoneNumber || !this.state.countryCode) { throw this.invalidArgument(); }
      const response = await this.client.getPhoneMethods({ authSessionId: this.authSessionId,
        userPhoneNumber: { phoneNumber, countryCode: this.state.countryCode }, device: this.hooks.device() });
      this.assertActive(); this.validateMethods(response.availableMethods);
      if (typeof response.prettifiedPhoneNumber !== 'string' || response.prettifiedPhoneNumber.length === 0) {
        this.diagnostics.event('phoneContextRejected', this.state.stage, LineErrorCode.REGISTRATION_PROTOCOL_ERROR);
        throw this.protocolError();
      }
      // APK k35.d0 -> EnterPhoneNumberResponse.normalizedPhoneNumber -> f45.q2:
      // retain the exact server value as the context for every later phone RPC.
      this.normalizedPhoneNumber = response.prettifiedPhoneNumber;
      this.selectedMethod = undefined; this.resendAt = 0;
      this.clearPullInstructions();
      this.state.availableMethods = response.availableMethods?.slice();
      this.state.prettifiedPhoneNumber = response.prettifiedPhoneNumber;
      this.diagnostics.event('phoneContextReady', this.state.stage);
      this.setStage('verification');
    });
  }

  requestVerification(method: LinePhoneVerificationMethod): Promise<void> {
    return this.run('requestVerification', ['verification'], async (): Promise<void> => {
      if ((method !== LinePhoneVerificationMethod.SMS && method !== LinePhoneVerificationMethod.IVR) ||
        this.state.availableMethods?.indexOf(method) === -1 || !this.state.availableMethods) { throw this.invalidArgument(); }
      if (method === LinePhoneVerificationMethod.SMS && this.now() < this.resendAt) {
        throw new MiniAppError(LineErrorCode.REGISTRATION_RETRY_LATER, 'LINE verification resend is cooling down');
      }
      this.diagnostics.event('verificationChannelSelected', method === LinePhoneVerificationMethod.SMS ? 'SMS' : 'IVR');
      const response = await this.client.requestCode({ authSessionId: this.authSessionId,
        userPhoneNumber: this.phone(), verifMethod: method });
      this.assertActive(); this.validateMethods(response.availableMethods);
      this.state.availableMethods = response.availableMethods?.slice();
      this.selectedMethod = method;
      this.clearPullInstructions();
      this.resendAt = method === LinePhoneVerificationMethod.SMS ? this.now() + RESEND_DELAY_MS : 0;
    });
  }

  verifyCode(code: string): Promise<void> {
    return this.run('verifyCode', ['verification'], async (): Promise<void> => {
      if (!this.selectedMethod || typeof code !== 'string' || !code) { throw this.invalidArgument(); }
      const pending = this.client.verifyCode({ authSessionId: this.authSessionId, userPhoneNumber: this.phone(), pinCode: code });
      code = '';
      this.acceptVerification(await pending);
    });
  }

  startPullSms(): Promise<void> {
    return this.run('startPullSms', ['verification'], async (): Promise<void> => {
      if (!this.state.availableMethods || this.state.availableMethods.indexOf(LinePhoneVerificationMethod.SMSPULL) < 0) {
        throw this.invalidArgument();
      }
      this.diagnostics.event('verificationChannelSelected', 'SMSPULL');
      const request: LineRegistrationPhoneRequest = { authSessionId: this.authSessionId, userPhoneNumber: this.phone() };
      const response = await this.client.fetchPullSms(request);
      this.assertActive();
      if (!response.destinationPhoneNumber || !response.pinCodeMessage) { throw this.protocolError(); }
      this.state.destinationPhoneNumber = response.destinationPhoneNumber;
      this.state.pinCodeMessage = response.pinCodeMessage; this.emit();
      this.assertActive();
      this.acceptVerification(await this.client.waitPullSms(request));
    });
  }

  validateProfile(displayName: string): Promise<void> {
    return this.run('validateProfile', ['profileInput', 'passwordInput'], async (): Promise<void> => {
      if (typeof displayName !== 'string' || !displayName) { throw this.invalidArgument(); }
      await this.client.validateProfile({ authSessionId: this.authSessionId, displayName });
      this.assertActive(); this.displayName = displayName; this.setStage('passwordInput');
    });
  }

  createAccount(password: string): Promise<void> {
    return this.run('createAccount', ['passwordInput'], async (): Promise<void> => {
      if (typeof password !== 'string' || !password) { throw this.invalidArgument(); }
      const parameters = await this.client.getPasswordParameters(this.authSessionId);
      this.assertActive();
      this.diagnostics.event('passwordHashStarted', this.state.stage);
      const hashing = this.crypto.hash(password, parameters.params, parameters.rules);
      password = '';
      let hash = await hashing;
      this.assertActive();
      this.diagnostics.event('passwordHashCompleted', this.state.stage);
      const setting = this.client.setPasswordHash({ authSessionId: this.authSessionId, password: hash });
      hash = ''; await setting; this.assertActive();
      const checkpoint: LineRegistrationCheckpoint = { displayName: this.displayName,
        countryCode: this.state.countryCode ?? '', countrySetOfEEA: this.countrySetOfEEA.slice(),
        nameUpdated: false, configurationsLoaded: false, countryUpdated: false, privacyUpdated: false };
      this.setStage('creating'); this.assertActive(); this.createInFlight = true;
      try {
        const response = await this.client.registerPhone(this.authSessionId);
        // UI may be cancelled; identity ownership is deliberately checked separately.
        this.hooks.assertIdentity();
        await this.hooks.acceptCreated(response, checkpoint);
        this.hooks.assertIdentity();
        this.diagnostics.event('accountCreatedPending', this.state.stage);
      } catch (error) {
        this.hooks.assertIdentity();
        if (error instanceof LineRegistrationError && error.service === 'registration') {
          if (this.active) { this.setStage('passwordInput'); }
          throw error;
        }
        if (this.active) { this.setStage('creationUncertain'); }
        throw new MiniAppError(LineErrorCode.REGISTRATION_CREATION_UNCERTAIN, 'LINE account creation outcome is uncertain');
      } finally {
        this.createInFlight = false;
        if (!this.active) { this.release(); }
      }
      this.assertActive();
      this.finalizer = new LineRegistrationFinalizer(checkpoint, this.hooks, (): void => this.assertActive());
      await this.finalize();
    });
  }

  submitPrivacy(privacy: LineRegistrationPrivacy): Promise<void> {
    return this.run('submitPrivacy', ['privacySettings'], async (): Promise<void> => {
      this.requireFinalizer().choosePrivacy(privacy); await this.finalize();
    });
  }

  skipAgeVerification(): Promise<void> {
    return this.run('skipAgeVerification', ['ageVerification'], async (): Promise<void> => {
      this.requireFinalizer().skipAge(); await this.finalize();
    });
  }

  resumeFinalization(): Promise<void> {
    return this.run('resumeFinalization', ['finalizing', 'privacySettings', 'ageVerification', 'agreementRequired'],
      async (): Promise<void> => { await this.finalize(); });
  }

  presentChallenge(context: common.UIAbilityContext): Promise<void> {
    return this.run('presentChallenge', ['challengeRequired'], async (): Promise<void> => {
      const challenge = this.challenge;
      if (!this.presentation || !challenge?.baseUrl || !challenge.token) { throw this.unsupported(); }
      let accepted: boolean;
      try { accepted = await this.presentation.presentChallenge(context, { baseUrl: challenge.baseUrl, token: challenge.token }); }
      catch (error) {
        if (error instanceof MiniAppError && error.code === LineErrorCode.REGISTRATION_CANCELLED) { this.cancel(); }
        throw this.sanitize(error as Object);
      }
      this.assertActive();
      if (accepted) { this.challenge = undefined; this.setStage(this.challengeReturn); }
    });
  }

  presentAgreement(context: common.UIAbilityContext): Promise<void> {
    return this.run('presentAgreement', ['agreementRequired'], async (): Promise<void> => {
      if (!this.presentation) { throw this.unsupported(); }
      const finalizer = this.requireFinalizer();
      const decision = await this.presentation.presentAgreement(context, finalizer.agreements(),
        async (): Promise<LineRegistrationAgreementContext> => {
          this.assertActive(); const result = await this.hooks.agreementContext(); this.assertActive(); return result;
        }, finalizer.countryPolicy());
      this.assertActive(); finalizer.recordAgreement(decision); await this.finalize();
    });
  }

  cancel(): void {
    if (!this.active) { return; }
    this.diagnostics.event('cancelled', this.state.stage, LineErrorCode.REGISTRATION_CANCELLED);
    this.active = false; this.challenge = undefined; this.normalizedPhoneNumber = ''; this.authSessionId = ''; this.displayName = '';
    try { this.presentation?.cancel(); } catch (_) { /* Window cleanup must not retain account ownership. */ }
    this.state = { stage: 'cancelled' };
    this.rejectResult(this.cancelled());
    if (!this.createInFlight) { this.release(); }
  }

  private async initialize(retrying: boolean = false): Promise<void> {
    const operation = this.diagnostics.start('action', retrying ? 'retryInitialization' : 'initialize');
    try {
      this.assertActive(); this.busy = true; this.emit(); this.assertActive();
      const checkpoint = await this.hooks.prepare(); this.assertActive();
      this.diagnostics.event('accountPrepared', this.state.stage);
      if (checkpoint) {
        this.diagnostics.event('pendingResumed', this.state.stage);
        this.state.countryCode = checkpoint.countryCode;
        this.finalizer = new LineRegistrationFinalizer(checkpoint, this.hooks, (): void => this.assertActive());
        await this.finalize();
      } else {
        this.hooks.device();
        this.diagnostics.event('devicePrepared', this.state.stage);
        if (!this.authSessionId) { this.authSessionId = await this.client.openSession(); this.assertActive(); }
        const country = await this.client.getCountryInfo({ authSessionId: this.authSessionId }); this.assertActive();
        if (!country.countrySetOfEEA || country.countrySetOfEEA.some((code: string): boolean => !/^[A-Z]{2}$/.test(code))) {
          throw this.protocolError();
        }
        this.countrySetOfEEA = country.countrySetOfEEA.slice();
        await this.client.lookupAvailableEap(this.authSessionId); this.assertActive();
        if (country.countryCode) {
          // A recommended country is not yet a user choice. EAP-only eligibility
          // must leave the phone-country selector available without admitting it.
          if (await this.allowCountry(country.countryCode)) { this.setStage('phoneInput'); }
          else { this.setStage('countrySelection', LineErrorCode.REGISTRATION_UNSUPPORTED); }
        }
        else { this.setStage('countrySelection'); }
      }
      this.diagnostics.complete(operation);
    } catch (error) {
      this.diagnostics.fail(operation, this.sanitize(error as Object));
      if (!this.active) {
        if (retrying) { throw this.cancelled(); }
        return;
      }
      const failure = this.sanitize(error as Object);
      if (!this.captureChallenge(error as Object, failure.code)) {
        this.setStage('failed', failure.code);
        this.active = false; this.release(); this.rejectResult(failure);
      }
      if (retrying) { throw failure; }
    } finally { this.busy = false; this.emit(); }
  }

  private async run(name: string, stages: LineRegistrationStage[], action: () => Promise<void>): Promise<void> {
    const operation = this.diagnostics.start('action', name);
    try {
      this.assertActive();
      if (this.busy || stages.indexOf(this.state.stage) < 0) {
        throw new MiniAppError(LineErrorCode.REGISTRATION_INVALID_STATE, 'LINE registration action is unavailable');
      }
    } catch (error) {
      const failure = MiniAppError.from(error as Object, LineErrorCode.REGISTRATION_FAILED,
        'LINE registration action could not complete');
      this.diagnostics.fail(operation, failure); throw failure;
    }
    this.busy = true; this.state.errorCode = undefined;
    try { this.emit(); this.assertActive(); await action(); this.assertActiveUnlessReady(); this.diagnostics.complete(operation); }
    catch (error) {
      if (!this.active && this.state.stage !== 'ready') {
        const failure = this.cancelled(); this.diagnostics.fail(operation, failure); throw failure;
      }
      const failure = this.sanitize(error as Object);
      this.diagnostics.fail(operation, failure);
      if (!this.captureChallenge(error as Object, failure.code)) { this.state.errorCode = failure.code; }
      throw failure;
    } finally { this.busy = false; this.emit(); }
  }

  private async allowCountry(countryCode: string): Promise<boolean> {
    const response = await this.client.getAllowedRegistrationMethod({ authSessionId: this.authSessionId, countryCode });
    this.assertActive();
    if (response.registrationMethod === LineRegistrationMethod.EAP_VERIF) { return false; }
    if (response.registrationMethod !== LineRegistrationMethod.PHONE_VERIF) { throw this.protocolError(); }
    this.state.countryCode = countryCode;
    return true;
  }

  private acceptVerification(response: LineRegistrationVerifyResponse): void {
    this.assertActive();
    if (response.accountExist === true) { throw this.unsupported(); }
    if (response.accountExist !== false || response.allowedToRegister !== true) {
      throw new MiniAppError(LineErrorCode.REGISTRATION_NOT_ALLOWED, 'LINE phone registration is not permitted');
    }
    this.clearPullInstructions(); this.setStage('profileInput');
  }

  private clearPullInstructions(): void {
    this.state.destinationPhoneNumber = undefined; this.state.pinCodeMessage = undefined;
  }

  private async finalize(): Promise<void> {
    this.setStage('finalizing');
    const stage = await this.requireFinalizer().resume(); this.assertActive();
    if (stage === 'ready') {
      this.hooks.complete(); this.setStage('ready'); this.resolveResult(); this.active = false; this.release();
    } else { this.setStage(stage); }
  }

  private requireFinalizer(): LineRegistrationFinalizer {
    if (!this.finalizer) { throw new MiniAppError(LineErrorCode.REGISTRATION_INVALID_STATE, 'LINE account is not created'); }
    return this.finalizer;
  }
  private phone(): LineRegistrationPhone {
    if (!this.normalizedPhoneNumber || !this.state.countryCode) {
      throw new MiniAppError(LineErrorCode.REGISTRATION_INVALID_STATE, 'LINE phone context is unavailable');
    }
    this.diagnostics.event('phoneContextUsed', this.state.stage);
    return { phoneNumber: this.normalizedPhoneNumber, countryCode: this.state.countryCode };
  }
  private validateMethods(methods?: LinePhoneVerificationMethod[]): void {
    if (!methods || methods.length === 0 || methods.some((value: LinePhoneVerificationMethod): boolean =>
      value !== LinePhoneVerificationMethod.SMS && value !== LinePhoneVerificationMethod.IVR && value !== LinePhoneVerificationMethod.SMSPULL)) {
      throw this.unsupported();
    }
  }
  private assertActiveUnlessReady(): void { if (this.state.stage !== 'ready') { this.assertActive(); } }
  private assertActive(): void { if (!this.active) { throw this.cancelled(); } this.hooks.assertIdentity(); }
  private release(): void {
    if (!this.released) { this.released = true; this.diagnostics.event('released', this.state.stage); this.hooks.release(); }
  }
  private setStage(stage: LineRegistrationStage, errorCode?: string): void {
    if (stage !== this.state.stage || errorCode !== this.state.errorCode) { this.diagnostics.event('stageChanged', stage, errorCode); }
    this.state.stage = stage; this.state.errorCode = errorCode; this.emit();
  }
  private emit(): void { if (this.active) { try { this.observer(this.getState()); } catch (_) { /* UI cannot alter protocol. */ } } }
  private sanitize(error: Object): MiniAppError {
    return new MiniAppError(error instanceof MiniAppError ? error.code : LineErrorCode.REGISTRATION_FAILED,
      'LINE registration action could not complete');
  }
  private captureChallenge(error: Object, code: string): boolean {
    if (!(error instanceof LineRegistrationError) || error.service !== 'registration' || error.wireCode !== 5 ||
      !error.webAuthDetails?.baseUrl || !error.webAuthDetails.token || this.state.stage === 'creationUncertain') { return false; }
    this.challenge = { baseUrl: error.webAuthDetails.baseUrl, token: error.webAuthDetails.token };
    this.challengeReturn = this.state.stage;
    this.setStage('challengeRequired', code);
    return true;
  }
  private cancelled(): MiniAppError { return new MiniAppError(LineErrorCode.REGISTRATION_CANCELLED, 'LINE registration was cancelled'); }
  private invalidArgument(): MiniAppError { return new MiniAppError(LineErrorCode.REGISTRATION_ILLEGAL_ARGUMENT, 'Invalid LINE registration input'); }
  private protocolError(): MiniAppError { return new MiniAppError(LineErrorCode.REGISTRATION_PROTOCOL_ERROR, 'Incomplete LINE registration response'); }
  private unsupported(): MiniAppError { return new MiniAppError(LineErrorCode.REGISTRATION_UNSUPPORTED, 'LINE registration step is unsupported'); }
}
