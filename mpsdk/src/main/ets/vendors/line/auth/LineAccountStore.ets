import { LineErrorCode } from '../LineErrorCode';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { SdkLogger } from '../../../logging/SdkLogger';
import { LineAccountCredential } from './LineAccountTypes';
import { LineClientRole } from '../network/LineTransport';
import { LineRegistrationCheckpoint } from '../registration/LineRegistrationSessionTypes';
import { LineCountryAgreement } from '../registration/LineRegistrationTypes';

// 版本与键名共同约束文件格式；升级格式时不得静默按新格式读取旧凭据。
const ACCOUNT_SCHEMA_VERSION: number = 2;
const ACCOUNT_PREFERENCES_NAME: string = 'atomicmpsdk.line.account';
const ACCOUNT_KEY: string = 'account.v1';

interface StoredAccount {
  version: number;
  mid: string;
  accessToken: string;
  refreshToken: string;
  certificate: string;
  loginSessionId: string;
  durationUntilRefreshInSec: number;
  expiresAt: number;
  role?: LineClientRole;
  stage?: 'ready' | 'pendingFinalization';
  registration?: LineRegistrationCheckpoint;
}

interface StorageFailure { code?: number; }

export interface RestoredLineAccount {
  credential: LineAccountCredential;
  expiresAt: number;
}

/** 使用宿主沙箱内的系统 Preferences 文件。所有存储失败仅记录日志，不阻断账号使用。 */
export class LineAccountStore {
  private readonly context?: common.Context;

  constructor(context?: common.Context) {
    this.context = context;
  }

  load(): RestoredLineAccount | undefined {
    try {
      const raw = this.preferences().getSync(ACCOUNT_KEY, '');
      if (raw === '') {
        return undefined;
      }
      if (typeof raw !== 'string') {
        throw new Error('Invalid account preferences');
      }
      const value = JSON.parse(raw) as StoredAccount;
      if (!value || (value.version !== 1 && value.version !== ACCOUNT_SCHEMA_VERSION) || typeof value.mid !== 'string' || !value.mid ||
        typeof value.accessToken !== 'string' || !value.accessToken ||
        typeof value.refreshToken !== 'string' || !value.refreshToken ||
        typeof value.certificate !== 'string' || typeof value.loginSessionId !== 'string' ||
        !Number.isSafeInteger(value.expiresAt) || value.expiresAt <= 0 ||
        !Number.isFinite(value.durationUntilRefreshInSec) || value.durationUntilRefreshInSec <= 0) {
        throw new Error('invalid account');
      }
      if (value.version === ACCOUNT_SCHEMA_VERSION &&
        ((value.role !== LineClientRole.PRIMARY && value.role !== LineClientRole.SECONDARY) ||
          (value.stage !== 'ready' && value.stage !== 'pendingFinalization') ||
          value.stage === 'pendingFinalization' &&
          (value.role !== LineClientRole.PRIMARY || !this.validCheckpoint(value.registration)))) {
        throw new Error('invalid account registration state');
      }
      return {
        credential: {
          role: value.version === 1 ? LineClientRole.SECONDARY : value.role,
          stage: value.version === 1 ? 'ready' : value.stage,
          registration: value.version === 2 && value.stage === 'pendingFinalization' ? value.registration : undefined,
          mid: value.mid,
          accessToken: value.accessToken,
          refreshToken: value.refreshToken,
          certificate: value.certificate,
          loginSessionId: value.loginSessionId,
          durationUntilRefreshInSec: value.durationUntilRefreshInSec,
          metaData: new Map<string, string>()
        }, expiresAt: value.expiresAt
      };
    } catch (error) {
      this.report('load', error as Object);
      return undefined;
    }
  }

  save(credential: LineAccountCredential, expiresAt: number): boolean {
    const value: StoredAccount = {
      version: ACCOUNT_SCHEMA_VERSION,
      mid: credential.mid,
      accessToken: credential.accessToken,
      refreshToken: credential.refreshToken,
      certificate: credential.certificate,
      loginSessionId: credential.loginSessionId,
      durationUntilRefreshInSec: credential.durationUntilRefreshInSec,
      expiresAt
      , role: credential.role ?? LineClientRole.SECONDARY,
      stage: credential.stage ?? 'ready',
      registration: credential.stage === 'pendingFinalization' ? credential.registration : undefined
    };
    try {
      const store = this.preferences();
      store.putSync(ACCOUNT_KEY, JSON.stringify(value));
      store.flushSync();
      return true;
    } catch (error) {
      this.report('save', error as Object);
      return false;
    }
  }

  clear(): boolean {
    try {
      const store = this.preferences();
      store.deleteSync(ACCOUNT_KEY);
      store.flushSync();
      return true;
    } catch (error) {
      this.report('clear', error as Object);
      return false;
    }
  }

  private report(operation: string, error: Object): void {
    const code: number | undefined = (error as StorageFailure).code;
    SdkLogger.warn('LineAccountStore', `${operation}Failed`, {
      code: typeof code === 'number' && Number.isSafeInteger(code) ? LineErrorCode.nativeDiagnostic(code) :
        error instanceof SyntaxError ? 'INVALID_JSON' : 'INVALID_OR_UNKNOWN_ERROR'
    });
  }

  private validCheckpoint(value?: LineRegistrationCheckpoint): boolean {
    if (!value || typeof value.displayName !== 'string' || !value.displayName ||
      typeof value.countryCode !== 'string' || !/^[A-Z]{2}$/.test(value.countryCode) ||
      !Array.isArray(value.countrySetOfEEA) || value.countrySetOfEEA.some((country: string): boolean =>
        typeof country !== 'string' || !/^[A-Z]{2}$/.test(country)) ||
      typeof value.nameUpdated !== 'boolean' || typeof value.configurationsLoaded !== 'boolean' ||
      typeof value.countryUpdated !== 'boolean' || typeof value.privacyUpdated !== 'boolean' ||
      value.profileRegion !== undefined && (typeof value.profileRegion !== 'string' || !/^[A-Z]{2}$/.test(value.profileRegion)) ||
      value.ageVerification !== undefined && value.ageVerification !== 'SKIPPED') { return false; }
    if (value.privacy !== undefined && (value.privacy === null || typeof value.privacy !== 'object' ||
      Array.isArray(value.privacy) || typeof value.privacy.privacySyncContacts !== 'boolean' ||
      typeof value.privacy.privacySearchByPhoneNumber !== 'boolean' ||
      value.privacy.privacySearchByUserid !== undefined && typeof value.privacy.privacySearchByUserid !== 'boolean')) { return false; }
    if (value.privacyUpdated && value.privacy === undefined) { return false; }
    const decision = value.countryDecision;
    if (decision !== undefined && (decision === null || typeof decision !== 'object' || Array.isArray(decision) ||
      (decision.policy !== LineCountryAgreement.GDPR && decision.policy !== LineCountryAgreement.ICNA &&
      decision.policy !== LineCountryAgreement.TH_PDPA && decision.policy !== LineCountryAgreement.ID_PDP) ||
      !Number.isSafeInteger(decision.timestampMs) || decision.timestampMs === 0)) { return false; }
    return !value.countryUpdated || decision !== undefined && value.profileRegion !== undefined;
  }

  private preferences(): preferences.Preferences {
    if (!this.context) {
      throw new Error('LINE persistence requires a host context');
    }
    return preferences.getPreferencesSync(this.context, { name: ACCOUNT_PREFERENCES_NAME });
  }
}
