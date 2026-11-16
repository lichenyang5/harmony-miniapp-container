import { LineCompactReader } from '../network/LineCompactCodec';
import { LineCompactType } from '../network/LineRpcConstants';
import { lineRegistrationInvalid } from './LineRegistrationError';
import { LineRegistrationCountryResponse, LineRegistrationAllowedResponse, LineRegistrationMethodsResponse, LineRegistrationCodeResponse, LineRegistrationUserProfile, LineRegistrationVerifyResponse, LineRegistrationPullSmsResponse, LineRegistrationCreateResponse, LineRegistrationTokenV3, LineRegistrationWebAuthDetails, LineRegistrationFailure, LineRegistrationProfile, LineRegistrationPendingAgreements, LineRegistrationConfigurations, LineRegistrationSettings } from './LineRegistrationTypes';

/** Concrete readers for the phone-registration fields; unknown fields are skipped by Compact. */
export class LineRegistrationReaders {
  static expect(type: number, expected: LineCompactType): void {
    if (type !== expected) { throw lineRegistrationInvalid(); }
  }

  static struct(reader: LineCompactReader, consume: (id: number, type: number) => boolean): void {
    const seen = new Set<number>();
    reader.struct((id: number, type: number): boolean => {
      if (seen.has(id)) { throw lineRegistrationInvalid(); }
      seen.add(id);
      return consume(id, type);
    });
  }

  /** APK schema y05.s. */
  static readCountry(reader: LineCompactReader): LineRegistrationCountryResponse {
    const result: LineRegistrationCountryResponse = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.countryCode = reader.string();
          return true;
        case 2:
          if (type !== LineCompactType.BOOLEAN_TRUE && type !== LineCompactType.BOOLEAN_FALSE) {
            throw lineRegistrationInvalid();
          }
          result.countryInEEA = type === LineCompactType.BOOLEAN_TRUE;
          return true;
        case 3:
          LineRegistrationReaders.expect(type, LineCompactType.SET);
          result.countrySetOfEEA = reader.strings();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema y05.r. */
  static readAllowed(reader: LineCompactReader): LineRegistrationAllowedResponse {
    const result: LineRegistrationAllowedResponse = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.I32);
          result.registrationMethod = reader.integer();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema y05.z. */
  static readMethods(reader: LineCompactReader): LineRegistrationMethodsResponse {
    const result: LineRegistrationMethodsResponse = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.LIST);
          result.availableMethods = reader.integers();
          return true;
        case 2:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.prettifiedPhoneNumber = reader.string();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema y05.q3. */
  static readCode(reader: LineCompactReader): LineRegistrationCodeResponse {
    const result: LineRegistrationCodeResponse = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.LIST);
          result.availableMethods = reader.integers();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema y05.b4. */
  static readUserProfile(reader: LineCompactReader): LineRegistrationUserProfile {
    const result: LineRegistrationUserProfile = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.displayName = reader.string();
          return true;
        case 2:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.profileImageUrl = reader.string();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema y05.j4 / y05.j. */
  static readVerify(reader: LineCompactReader): LineRegistrationVerifyResponse {
    const result: LineRegistrationVerifyResponse = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          if (type !== LineCompactType.BOOLEAN_TRUE && type !== LineCompactType.BOOLEAN_FALSE) {
            throw lineRegistrationInvalid();
          }
          result.accountExist = type === LineCompactType.BOOLEAN_TRUE;
          return true;
        case 2:
          if (type !== LineCompactType.BOOLEAN_TRUE && type !== LineCompactType.BOOLEAN_FALSE) {
            throw lineRegistrationInvalid();
          }
          result.sameUdidFromAccount = type === LineCompactType.BOOLEAN_TRUE;
          return true;
        case 3:
          if (type !== LineCompactType.BOOLEAN_TRUE && type !== LineCompactType.BOOLEAN_FALSE) {
            throw lineRegistrationInvalid();
          }
          result.allowedToRegister = type === LineCompactType.BOOLEAN_TRUE;
          return true;
        case 11:
          LineRegistrationReaders.expect(type, LineCompactType.STRUCT);
          result.userProfile = LineRegistrationReaders.readUserProfile(reader);
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema y05.p. */
  static readPullSms(reader: LineCompactReader): LineRegistrationPullSmsResponse {
    const result: LineRegistrationPullSmsResponse = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.pinCodeMessage = reader.string();
          return true;
        case 2:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.destinationPhoneNumber = reader.string();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema y05.n3. */
  static readCreate(reader: LineCompactReader): LineRegistrationCreateResponse {
    const result: LineRegistrationCreateResponse = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.authToken = reader.string();
          return true;
        case 2:
          LineRegistrationReaders.expect(type, LineCompactType.STRUCT);
          result.tokenV3IssueResult = LineRegistrationReaders.readTokenV3(reader);
          return true;
        case 3:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.mid = reader.string();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema y05.z3. */
  static readTokenV3(reader: LineCompactReader): LineRegistrationTokenV3 {
    const result: LineRegistrationTokenV3 = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.accessToken = reader.string();
          return true;
        case 2:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.refreshToken = reader.string();
          return true;
        case 3:
          LineRegistrationReaders.expect(type, LineCompactType.I64);
          result.durationUntilRefreshInSec = reader.long();
          return true;
        case 5:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.loginSessionId = reader.string();
          return true;
        case 6:
          LineRegistrationReaders.expect(type, LineCompactType.I64);
          result.tokenIssueTimeEpochSec = reader.long();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema y05.l4. */
  static readWebAuthDetails(reader: LineCompactReader): LineRegistrationWebAuthDetails {
    const result: LineRegistrationWebAuthDetails = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.baseUrl = reader.string();
          return true;
        case 2:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.token = reader.string();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema y05.f. */
  static readAuthFailure(reader: LineCompactReader): LineRegistrationFailure {
    const result: LineRegistrationFailure = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.I32);
          result.code = reader.integer();
          return true;
        case 11:
          LineRegistrationReaders.expect(type, LineCompactType.STRUCT);
          result.webAuthDetails = LineRegistrationReaders.readWebAuthDetails(reader);
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema gp8.vh. */
  static readTalkFailure(reader: LineCompactReader): LineRegistrationFailure {
    const result: LineRegistrationFailure = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.I32);
          result.code = reader.integer();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema gp8.xe. */
  static readProfile(reader: LineCompactReader): LineRegistrationProfile {
    const result: LineRegistrationProfile = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.mid = reader.string();
          return true;
        case 12:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.regionCode = reader.string();
          return true;
        case 10:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.phone = reader.string();
          return true;
        case 20:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.displayName = reader.string();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema gp8.oe. */
  static readPendingAgreements(reader: LineCompactReader): LineRegistrationPendingAgreements {
    const result: LineRegistrationPendingAgreements = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.LIST);
          result.pendingAgreements = reader.integers();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema gp8.d7. */
  static readConfigurations(reader: LineCompactReader): LineRegistrationConfigurations {
    const result: LineRegistrationConfigurations = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 1:
          LineRegistrationReaders.expect(type, LineCompactType.I64);
          result.revision = reader.long();
          return true;
        case 2:
          LineRegistrationReaders.expect(type, LineCompactType.MAP);
          result.configMap = reader.stringMap();
          return true;
        default: return false;
      }
    });
    return result;
  }

  /** APK schema gp8.ah. */
  static readSettings(reader: LineCompactReader): LineRegistrationSettings {
    const result: LineRegistrationSettings = {};
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      switch (id) {
        case 20:
          if (type !== LineCompactType.BOOLEAN_TRUE && type !== LineCompactType.BOOLEAN_FALSE) {
            throw lineRegistrationInvalid();
          }
          result.privacySyncContacts = type === LineCompactType.BOOLEAN_TRUE;
          return true;
        case 21:
          if (type !== LineCompactType.BOOLEAN_TRUE && type !== LineCompactType.BOOLEAN_FALSE) {
            throw lineRegistrationInvalid();
          }
          result.privacySearchByPhoneNumber = type === LineCompactType.BOOLEAN_TRUE;
          return true;
        case 22:
          if (type !== LineCompactType.BOOLEAN_TRUE && type !== LineCompactType.BOOLEAN_FALSE) {
            throw lineRegistrationInvalid();
          }
          result.privacySearchByUserid = type === LineCompactType.BOOLEAN_TRUE;
          return true;
        case 74:
          LineRegistrationReaders.expect(type, LineCompactType.BINARY);
          result.privacyPolicyVersion = reader.string();
          return true;
        case 80:
          LineRegistrationReaders.expect(type, LineCompactType.I64);
          result.agreementGdpr = reader.long();
          return true;
        case 94:
          LineRegistrationReaders.expect(type, LineCompactType.I64);
          result.agreementIcna = reader.long();
          return true;
        case 122:
          LineRegistrationReaders.expect(type, LineCompactType.I64);
          result.agreementPdp = reader.long();
          return true;
        case 105:
          LineRegistrationReaders.expect(type, LineCompactType.I64);
          result.agreementPdpa = reader.long();
          return true;
        default: return false;
      }
    });
    return result;
  }
}
