import { common } from '@kit.AbilityKit';
import { LineRegistrationPasswordCrypto } from './LineRegistrationCrypto';
import { LineRegistrationDeviceInfo } from './LineRegistrationDevice';
import { LineTransport } from '../network/LineTransport';
import {
  LineCountryAgreement, LinePhoneVerificationMethod, LineRegistrationAllowedRequest, LineRegistrationAllowedResponse,
  LineRegistrationCodeRequest, LineRegistrationCodeResponse, LineRegistrationCountryRequest, LineRegistrationCountryResponse,
  LineRegistrationCreateResponse, LineRegistrationEapResponse, LineRegistrationMethodsRequest, LineRegistrationMethodsResponse,
  LineRegistrationPasswordRequest, LineRegistrationPasswordResponse, LineRegistrationPhoneRequest,
  LineRegistrationProfileRequest, LineRegistrationPullSmsResponse, LineRegistrationVerifyRequest,
  LineRegistrationVerifyResponse, LineRegistrationPrivacy, LineRegistrationWebAuthDetails,
  LineRegistrationProfile, LineRegistrationPendingAgreements, LineRegistrationConfigurationsRequest,
  LineRegistrationConfigurations, LineRegistrationSettings
} from './LineRegistrationTypes';

export type LineRegistrationStage = 'initializing' | 'countrySelection' | 'phoneInput' | 'verification' |
  'profileInput' | 'passwordInput' | 'creating' | 'creationUncertain' | 'finalizing' | 'privacySettings' |
  'ageVerification' | 'challengeRequired' | 'agreementRequired' | 'ready' | 'cancelled' | 'failed';

/** A fresh copy is delivered to observers; no authentication material belongs here. */
export interface LinePhoneRegistrationState {
  stage: LineRegistrationStage;
  countryCode?: string;
  availableMethods?: LinePhoneVerificationMethod[];
  prettifiedPhoneNumber?: string;
  resendRemainingMs?: number;
  destinationPhoneNumber?: string;
  pinCodeMessage?: string;
  errorCode?: string;
  busy?: boolean;
}

export interface LineRegistrationAgreementDecision {
  policy: LineCountryAgreement;
  /** Positive acceptance or negative explicit refusal, in safe integer milliseconds. */
  timestampMs: number;
}

/** Persisted progress contains only explicit choices and completed finalization steps. */
export interface LineRegistrationCheckpoint {
  displayName: string;
  countryCode: string;
  countrySetOfEEA: string[];
  nameUpdated: boolean;
  profileRegion?: string;
  configurationsLoaded: boolean;
  privacy?: LineRegistrationPrivacy;
  ageVerification?: 'SKIPPED';
  countryDecision?: LineRegistrationAgreementDecision;
  countryUpdated: boolean;
  privacyUpdated: boolean;
}

export interface LineRegistrationOperations {
  openSession(): Promise<string>;
  getCountryInfo(request: LineRegistrationCountryRequest): Promise<LineRegistrationCountryResponse>;
  lookupAvailableEap(session: string): Promise<LineRegistrationEapResponse>;
  getAllowedRegistrationMethod(request: LineRegistrationAllowedRequest): Promise<LineRegistrationAllowedResponse>;
  getPhoneMethods(request: LineRegistrationMethodsRequest): Promise<LineRegistrationMethodsResponse>;
  requestCode(request: LineRegistrationCodeRequest): Promise<LineRegistrationCodeResponse>;
  verifyCode(request: LineRegistrationVerifyRequest): Promise<LineRegistrationVerifyResponse>;
  fetchPullSms(request: LineRegistrationPhoneRequest): Promise<LineRegistrationPullSmsResponse>;
  waitPullSms(request: LineRegistrationPhoneRequest): Promise<LineRegistrationVerifyResponse>;
  validateProfile(request: LineRegistrationProfileRequest): Promise<void>;
  getPasswordParameters(session: string): Promise<LineRegistrationPasswordResponse>;
  setPasswordHash(request: LineRegistrationPasswordRequest): Promise<void>;
  registerPhone(session: string): Promise<LineRegistrationCreateResponse>;
}

export interface LineRegistrationTalkOperations {
  updateName(name: string): Promise<void>;
  getProfile(): Promise<LineRegistrationProfile>;
  getPendingAgreements(): Promise<LineRegistrationPendingAgreements>;
  getConfigurations(request: LineRegistrationConfigurationsRequest): Promise<LineRegistrationConfigurations>;
  getSettings(): Promise<LineRegistrationSettings>;
  updatePrivacy(privacy: LineRegistrationPrivacy): Promise<number[]>;
  updateCountryAgreement(policy: LineCountryAgreement, timestampMs: number): Promise<number[]>;
}

/** Internal SDK window port. Never exported from Index or accepted in public account options. */
export interface LineRegistrationAgreementContext {
  endpoint: string;
  headers: Record<string, string>;
}

export interface LineRegistrationPresentation {
  presentChallenge(context: common.UIAbilityContext, details: LineRegistrationWebAuthDetails): Promise<boolean>;
  presentAgreement(context: common.UIAbilityContext, agreements: number[],
    accountContext: () => Promise<LineRegistrationAgreementContext>,
    countryPolicy?: LineCountryAgreement): Promise<LineRegistrationAgreementDecision | undefined>;
  cancel(): void;
}

/** Internal constructor seam: per-manager services, per-session window factory, no mutable global hook. */
export interface LineRegistrationDependencies {
  client?: LineRegistrationOperations;
  crypto?: LineRegistrationPasswordCrypto;
  device?: LineRegistrationDeviceInfo;
  talkFactory?: (transport: LineTransport, accessToken: string) => LineRegistrationTalkOperations;
  presentationFactory?: () => LineRegistrationPresentation;
  accountEndpoint?: () => Promise<string>;
  monotonicNow?: () => number;
}

export interface LineRegistrationSessionHooks {
  prepare: () => Promise<LineRegistrationCheckpoint | undefined>;
  device: () => LineRegistrationDeviceInfo;
  acceptCreated: (response: LineRegistrationCreateResponse, checkpoint: LineRegistrationCheckpoint) => Promise<void>;
  talk: () => LineRegistrationTalkOperations;
  save: (checkpoint: LineRegistrationCheckpoint) => void;
  complete: () => void;
  release: () => void;
  assertIdentity: () => void;
  assertProfile: (mid: string) => void;
  refreshPending: () => Promise<void>;
  agreementContext: () => Promise<LineRegistrationAgreementContext>;
}
