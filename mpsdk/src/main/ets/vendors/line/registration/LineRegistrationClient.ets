import { LineRegistrationOperations, LineRegistrationTalkOperations } from './LineRegistrationSessionTypes';
import { LineErrorCode } from '../LineErrorCode';
import { LineRegistrationRpcMethod, LineRegistrationTalkRpcMethod } from '../network/LineRpcConstants';
import { LineAccessKind, LineClientRole, LineTransport } from '../network/LineTransport';
import { LineCompactReader, LineCompactWriter } from '../network/LineCompactCodec';
import { LineCompactType, LineRpcPath, LineRpcTimeout } from '../network/LineRpcConstants';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineRegistrationDiagnostics } from './LineRegistrationDiagnostics';
import { LineRegistrationCodec } from './LineRegistrationCodec';
import { lineRegistrationInvalid } from './LineRegistrationError';
import { LineRegistrationReaders } from './LineRegistrationReaders';
import { LineRegistrationTalkCodec } from './LineRegistrationTalkCodec';
import {
  LineCountryAgreement, LineRegistrationAllowedRequest, LineRegistrationAllowedResponse,
  LineRegistrationCodeRequest, LineRegistrationCodeResponse, LineRegistrationConfigurations,
  LineRegistrationConfigurationsRequest, LineRegistrationCountryRequest, LineRegistrationCountryResponse,
  LineRegistrationCreateResponse, LineRegistrationEapResponse, LineRegistrationMethodsRequest,
  LineRegistrationMethodsResponse, LineRegistrationPasswordRequest, LineRegistrationPasswordResponse,
  LineRegistrationPendingAgreements, LineRegistrationPhoneRequest, LineRegistrationPrivacy,
  LineRegistrationProfile, LineRegistrationProfileRequest, LineRegistrationPullSmsResponse,
  LineRegistrationSettings, LineRegistrationVerifyRequest, LineRegistrationVerifyResponse
} from './LineRegistrationTypes';

/** One-shot protocol calls only. Cancellation, retries and registration state belong to the session. */
export class LineRegistrationClient implements LineRegistrationOperations {
  private readonly transport: LineTransport;
  private readonly diagnostics: LineRegistrationDiagnostics;
  private sequence: number = 0;

  constructor(transport: LineTransport, diagnostics: LineRegistrationDiagnostics = new LineRegistrationDiagnostics()) {
    this.transport = transport; this.diagnostics = diagnostics;
  }

  private async call<T>(method: string, sequence: number, body: Uint8Array,
    parse: (reader: LineCompactReader) => T, successType: LineCompactType = LineCompactType.STRUCT,
    sessionAccess?: string): Promise<T> {
    const operation = this.diagnostics.start('rpc', method);
    try {
      const response: Uint8Array = await this.transport.send({
        method, body, role: LineClientRole.PRIMARY,
        path: sessionAccess === undefined ? LineRpcPath.REGISTRATION : LineRpcPath.REGISTRATION_POLL,
        accessKind: sessionAccess === undefined ? LineAccessKind.NONE : LineAccessKind.REGISTRATION_SESSION,
        sessionAccess,
        timeoutMs: LineRpcTimeout.REQUEST_MS
      });
      const result = LineRegistrationCodec.response(response, method, sequence, successType, parse);
      this.diagnostics.complete(operation);
      return result;
    } catch (error) {
      const failure = MiniAppError.from(error as Object, LineErrorCode.REGISTRATION_FAILED,
        'LINE registration request failed');
      this.diagnostics.fail(operation, failure);
      throw failure;
    }
  }

  async openSession(metaData: Map<string, string> = new Map<string, string>()): Promise<string> {
    const sequence: number = ++this.sequence;
    const session: string = await this.call(LineRegistrationRpcMethod.OPEN_SESSION, sequence, LineRegistrationCodec.openSession(metaData, sequence),
      (reader: LineCompactReader): string => reader.string(), LineCompactType.BINARY);
    if (!session) { throw lineRegistrationInvalid(); }
    return session;
  }

  getCountryInfo(request: LineRegistrationCountryRequest): Promise<LineRegistrationCountryResponse> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.COUNTRY, sequence, LineRegistrationCodec.country(request, sequence),
      LineRegistrationReaders.readCountry);
  }

  lookupAvailableEap(authSessionId: string): Promise<LineRegistrationEapResponse> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.AVAILABLE_EAP, sequence,
      LineRegistrationCodec.session(LineRegistrationRpcMethod.AVAILABLE_EAP, authSessionId, sequence),
      (reader: LineCompactReader): LineRegistrationEapResponse => {
        const result: LineRegistrationEapResponse = {};
        LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
          if (id !== 1) { return false; }
          LineRegistrationReaders.expect(type, LineCompactType.LIST);
          result.availableEap = reader.integers();
          return true;
        });
        return result;
      });
  }

  getAllowedRegistrationMethod(request: LineRegistrationAllowedRequest): Promise<LineRegistrationAllowedResponse> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.ALLOWED, sequence, LineRegistrationCodec.allowed(request, sequence),
      LineRegistrationReaders.readAllowed);
  }

  getPhoneMethods(request: LineRegistrationMethodsRequest): Promise<LineRegistrationMethodsResponse> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.PHONE_METHODS, sequence, LineRegistrationCodec.methods(request, sequence),
      LineRegistrationReaders.readMethods);
  }

  requestCode(request: LineRegistrationCodeRequest): Promise<LineRegistrationCodeResponse> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.REQUEST_CODE, sequence, LineRegistrationCodec.requestCode(request, sequence),
      LineRegistrationReaders.readCode);
  }

  verifyCode(request: LineRegistrationVerifyRequest): Promise<LineRegistrationVerifyResponse> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.VERIFY_CODE, sequence, LineRegistrationCodec.verify(request, sequence),
      LineRegistrationReaders.readVerify);
  }

  fetchPullSms(request: LineRegistrationPhoneRequest): Promise<LineRegistrationPullSmsResponse> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.FETCH_SMS, sequence,
      LineRegistrationCodec.phoneRequest(LineRegistrationRpcMethod.FETCH_SMS, request, sequence), LineRegistrationReaders.readPullSms);
  }

  waitPullSms(request: LineRegistrationPhoneRequest): Promise<LineRegistrationVerifyResponse> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.WAIT_SMS, sequence,
      LineRegistrationCodec.phoneRequest(LineRegistrationRpcMethod.WAIT_SMS, request, sequence),
      LineRegistrationReaders.readVerify, LineCompactType.STRUCT, request.authSessionId);
  }

  validateProfile(request: LineRegistrationProfileRequest): Promise<void> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.VALIDATE_PROFILE, sequence, LineRegistrationCodec.profile(request, sequence),
      LineRegistrationCodec.empty);
  }

  getPasswordParameters(authSessionId: string): Promise<LineRegistrationPasswordResponse> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.PASSWORD_PARAMETERS, sequence,
      LineRegistrationCodec.session(LineRegistrationRpcMethod.PASSWORD_PARAMETERS, authSessionId, sequence),
      LineRegistrationCodec.passwordParameters);
  }

  setPasswordHash(request: LineRegistrationPasswordRequest): Promise<void> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.SET_PASSWORD, sequence, LineRegistrationCodec.password(request, sequence),
      LineRegistrationCodec.empty);
  }

  registerPhone(authSessionId: string): Promise<LineRegistrationCreateResponse> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationRpcMethod.REGISTER_PHONE, sequence,
      LineRegistrationCodec.session(LineRegistrationRpcMethod.REGISTER_PHONE, authSessionId, sequence, true),
      LineRegistrationReaders.readCreate);
  }
}

/** Account-authenticated finalization calls; never accepts a registration session as implicit identity. */
export class LineRegistrationTalkClient implements LineRegistrationTalkOperations {
  private readonly transport: LineTransport;
  private readonly accessToken: string;
  private readonly role: LineClientRole;
  private readonly diagnostics: LineRegistrationDiagnostics;
  private sequence: number = 0;

  constructor(transport: LineTransport, accessToken: string, role: LineClientRole = LineClientRole.PRIMARY,
    diagnostics: LineRegistrationDiagnostics = new LineRegistrationDiagnostics()) {
    if (!accessToken || (role !== LineClientRole.PRIMARY && role !== LineClientRole.SECONDARY)) {
      throw new MiniAppError(LineErrorCode.REGISTRATION_ILLEGAL_ARGUMENT, 'LINE account identity is required');
    }
    this.transport = transport;
    this.accessToken = accessToken;
    this.role = role;
    this.diagnostics = diagnostics;
  }

  private async call<T>(method: string, sequence: number, body: Uint8Array,
    parse: (reader: LineCompactReader) => T, type: LineCompactType = LineCompactType.STRUCT,
    voidResult: boolean = false): Promise<T> {
    const operation = this.diagnostics.start('rpc', method);
    try {
      const response: Uint8Array = await this.transport.send({
        path: LineRpcPath.ACCOUNT_TALK, method, body, role: this.role,
        accessKind: LineAccessKind.ACCOUNT, sessionAccess: this.accessToken
      });
      const result = LineRegistrationCodec.response(response, method, sequence, type, parse, true, voidResult);
      this.diagnostics.complete(operation);
      return result;
    } catch (error) {
      const failure = MiniAppError.from(error as Object, LineErrorCode.REGISTRATION_FAILED,
        'LINE finalization request failed');
      this.diagnostics.fail(operation, failure); throw failure;
    }
  }

  updateName(displayName: string, reqSeq: number = 0): Promise<void> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationTalkRpcMethod.UPDATE_NAME, sequence,
      LineRegistrationTalkCodec.updateName(displayName, reqSeq, sequence), LineRegistrationCodec.empty,
      LineCompactType.STRUCT, true);
  }

  getProfile(): Promise<LineRegistrationProfile> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationTalkRpcMethod.PROFILE, sequence, LineRegistrationTalkCodec.initialization(LineRegistrationTalkRpcMethod.PROFILE, sequence),
      LineRegistrationReaders.readProfile);
  }

  getPendingAgreements(): Promise<LineRegistrationPendingAgreements> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationTalkRpcMethod.PENDING_AGREEMENTS, sequence,
      LineRegistrationCodec.request(LineRegistrationTalkRpcMethod.PENDING_AGREEMENTS, sequence, (_writer: LineCompactWriter): void => {}, false),
      LineRegistrationReaders.readPendingAgreements);
  }

  getConfigurations(request: LineRegistrationConfigurationsRequest): Promise<LineRegistrationConfigurations> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationTalkRpcMethod.CONFIGURATIONS, sequence, LineRegistrationTalkCodec.configurations(request, sequence),
      LineRegistrationReaders.readConfigurations);
  }

  getSettings(): Promise<LineRegistrationSettings> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationTalkRpcMethod.SETTINGS, sequence, LineRegistrationTalkCodec.initialization(LineRegistrationTalkRpcMethod.SETTINGS, sequence),
      LineRegistrationReaders.readSettings);
  }

  updatePrivacy(request: LineRegistrationPrivacy, reqSeq: number = 0): Promise<number[]> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationTalkRpcMethod.UPDATE_SETTINGS, sequence,
      LineRegistrationTalkCodec.privacy(request, reqSeq, sequence),
      (reader: LineCompactReader): number[] => reader.integers(), LineCompactType.SET);
  }

  updateCountryAgreement(policy: LineCountryAgreement, timestampMs: number, reqSeq: number = 0): Promise<number[]> {
    const sequence: number = ++this.sequence;
    return this.call(LineRegistrationTalkRpcMethod.UPDATE_SETTINGS, sequence,
      LineRegistrationTalkCodec.countryAgreement(policy, timestampMs, reqSeq, sequence),
      (reader: LineCompactReader): number[] => reader.integers(), LineCompactType.SET);
  }
}
