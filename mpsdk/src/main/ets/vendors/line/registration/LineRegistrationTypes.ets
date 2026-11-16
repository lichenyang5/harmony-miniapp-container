import { LinePasswordHashParameters, LinePasswordRule } from './LineRegistrationCrypto';
import { LineRegistrationDeviceInfo } from './LineRegistrationDevice';

export enum LineRegistrationMethod {
  PHONE_VERIF = 1,
  EAP_VERIF = 2
}

export enum LinePhoneVerificationMethod {
  UNKNOWN = 0,
  SMS = 1,
  IVR = 2,
  SMSPULL = 3
}

export enum LineCountryAgreement {
  GDPR = 'GDPR',
  ICNA = 'ICNA',
  TH_PDPA = 'TH_PDPA',
  ID_PDP = 'ID_PDP'
}

export interface LineRegistrationPhone {
  phoneNumber: string;
  countryCode: string;
}

export interface LineRegistrationSimCard {
  countryCode: string;
  hni: string;
  carrierName: string;
}

export interface LineRegistrationCountryRequest {
  authSessionId: string;
  simCard?: LineRegistrationSimCard;
}

export interface LineRegistrationAllowedRequest {
  authSessionId: string;
  countryCode: string;
}

export interface LineRegistrationPhoneRequest {
  authSessionId: string;
  userPhoneNumber: LineRegistrationPhone;
}

export interface LineRegistrationMethodsRequest extends LineRegistrationPhoneRequest {
  device: LineRegistrationDeviceInfo;
}

export interface LineRegistrationCodeRequest extends LineRegistrationPhoneRequest {
  verifMethod: LinePhoneVerificationMethod;
}

export interface LineRegistrationVerifyRequest extends LineRegistrationPhoneRequest {
  pinCode: string;
}

export interface LineRegistrationProfileRequest {
  authSessionId: string;
  displayName: string;
}

export interface LineRegistrationPasswordRequest {
  authSessionId: string;
  password: string;
}

// Descriptor requiredness is unknown. Missing response fields remain absent so the
// session boundary can reject incomplete/unknown server state rather than invent defaults.
export interface LineRegistrationCountryResponse {
  countryCode?: string;
  countryInEEA?: boolean;
  countrySetOfEEA?: string[];
}

export interface LineRegistrationAllowedResponse {
  registrationMethod?: LineRegistrationMethod;
}

export interface LineRegistrationEapResponse {
  availableEap?: number[];
}

export interface LineRegistrationMethodsResponse {
  availableMethods?: LinePhoneVerificationMethod[];
  prettifiedPhoneNumber?: string;
}

export interface LineRegistrationCodeResponse {
  availableMethods?: LinePhoneVerificationMethod[];
}

export interface LineRegistrationUserProfile {
  displayName?: string;
  profileImageUrl?: string;
}

export interface LineRegistrationVerifyResponse {
  accountExist?: boolean;
  sameUdidFromAccount?: boolean;
  allowedToRegister?: boolean;
  userProfile?: LineRegistrationUserProfile;
}

export interface LineRegistrationPullSmsResponse {
  pinCodeMessage?: string;
  destinationPhoneNumber?: string;
}

export interface LineRegistrationPasswordResponse {
  params: LinePasswordHashParameters;
  rules: LinePasswordRule[];
}

export interface LineRegistrationTokenV3 {
  accessToken?: string;
  refreshToken?: string;
  durationUntilRefreshInSec?: number;
  loginSessionId?: string;
  tokenIssueTimeEpochSec?: number;
}

export interface LineRegistrationCreateResponse {
  authToken?: string;
  tokenV3IssueResult?: LineRegistrationTokenV3;
  mid?: string;
}

export interface LineRegistrationWebAuthDetails {
  baseUrl?: string;
  token?: string;
}

export interface LineRegistrationFailure {
  code?: number;
  webAuthDetails?: LineRegistrationWebAuthDetails;
}

export interface LineRegistrationProfile {
  mid?: string;
  regionCode?: string;
  phone?: string;
  displayName?: string;
}

export interface LineRegistrationPendingAgreements {
  pendingAgreements?: number[];
}

export interface LineRegistrationConfigurationsRequest {
  revision: number;
  regionOfUsim: string;
  regionOfTelephone: string;
  regionOfLocale: string;
  carrier: string;
}

export interface LineRegistrationConfigurations {
  revision?: number;
  configMap?: Map<string, string>;
}

export interface LineRegistrationPrivacy {
  privacySyncContacts: boolean;
  privacySearchByPhoneNumber: boolean;
  privacySearchByUserid?: boolean;
}

export interface LineRegistrationSettings {
  privacySyncContacts?: boolean;
  privacySearchByPhoneNumber?: boolean;
  privacySearchByUserid?: boolean;
  agreementGdpr?: number;
  agreementIcna?: number;
  agreementPdpa?: number;
  agreementPdp?: number;
  privacyPolicyVersion?: string;
}
