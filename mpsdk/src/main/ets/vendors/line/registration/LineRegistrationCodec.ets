import { LineErrorCode } from '../LineErrorCode';
import { LineRegistrationRpcMethod } from '../network/LineRpcConstants';
import { LineCompactCodec, LineCompactReader, LineCompactWriter } from '../network/LineCompactCodec';
import { LineCompactLimits, LineCompactMessage, LineCompactType } from '../network/LineRpcConstants';
import { MiniAppError } from '../../../core/MiniAppError';
import { LinePasswordHashParameters, LinePasswordRule } from './LineRegistrationCrypto';
import { lineRegistrationInvalid, LineRegistrationError } from './LineRegistrationError';
import { LineRegistrationReaders } from './LineRegistrationReaders';
import {
  LineRegistrationAllowedRequest, LineRegistrationCodeRequest, LineRegistrationCountryRequest,
  LineRegistrationFailure, LineRegistrationMethodsRequest, LineRegistrationPasswordRequest,
  LineRegistrationPasswordResponse, LineRegistrationPhone, LineRegistrationPhoneRequest,
  LineRegistrationProfileRequest, LineRegistrationVerifyRequest
} from './LineRegistrationTypes';

interface PasswordParametersWire {
  hmacKey?: string;
  salt?: string;
  nrp?: string;
  dkLen?: number;
}

/** PAIS Compact envelope and phone request writers. No network or session state. */
export class LineRegistrationCodec {
  static writer(method: string, sequence: number): LineCompactWriter {
    const writer = new LineCompactWriter();
    writer.byte(LineCompactMessage.PROTOCOL_ID);
    writer.byte(LineCompactMessage.CALL_HEADER);
    writer.uint(sequence);
    writer.string(method);
    return writer;
  }

  static text(writer: LineCompactWriter, id: number, value: string, previous: number = 0): void {
    writer.field(id, LineCompactType.BINARY, previous);
    writer.string(value);
  }

  static phone(writer: LineCompactWriter, phone: LineRegistrationPhone): void {
    LineRegistrationCodec.text(writer, 1, phone.phoneNumber);
    LineRegistrationCodec.text(writer, 2, phone.countryCode, 1);
    writer.byte(LineCompactType.STOP);
  }

  static request(method: string, sequence: number,
    write: (writer: LineCompactWriter) => void, wrapped: boolean = true): Uint8Array {
    const writer = LineRegistrationCodec.writer(method, sequence);
    if (wrapped) { writer.field(1, LineCompactType.STRUCT); }
    write(writer);
    if (wrapped) { writer.byte(LineCompactType.STOP); }
    writer.byte(LineCompactType.STOP);
    return writer.result();
  }

  static openSession(metaData: Map<string, string>, sequence: number): Uint8Array {
    return LineRegistrationCodec.request(LineRegistrationRpcMethod.OPEN_SESSION, sequence, (writer: LineCompactWriter): void => {
      writer.field(1, LineCompactType.MAP);
      writer.uint(metaData.size);
      if (metaData.size > 0) {
        writer.byte(0x88);
        metaData.forEach((value: string, key: string): void => { writer.string(key); writer.string(value); });
      }
    });
  }

  static country(request: LineRegistrationCountryRequest, sequence: number): Uint8Array {
    return LineRegistrationCodec.request(LineRegistrationRpcMethod.COUNTRY, sequence, (writer: LineCompactWriter): void => {
      LineRegistrationCodec.text(writer, 1, request.authSessionId);
      if (request.simCard) {
        writer.field(11, LineCompactType.STRUCT, 1);
        LineRegistrationCodec.text(writer, 1, request.simCard.countryCode);
        LineRegistrationCodec.text(writer, 2, request.simCard.hni, 1);
        LineRegistrationCodec.text(writer, 3, request.simCard.carrierName, 2);
        writer.byte(LineCompactType.STOP);
      }
    }, false);
  }

  static allowed(request: LineRegistrationAllowedRequest, sequence: number): Uint8Array {
    return LineRegistrationCodec.request(LineRegistrationRpcMethod.ALLOWED, sequence, (writer: LineCompactWriter): void => {
      LineRegistrationCodec.text(writer, 1, request.authSessionId);
      LineRegistrationCodec.text(writer, 2, request.countryCode, 1);
    }, false);
  }

  static methods(request: LineRegistrationMethodsRequest, sequence: number): Uint8Array {
    return LineRegistrationCodec.request(LineRegistrationRpcMethod.PHONE_METHODS, sequence,
      (writer: LineCompactWriter): void => {
        LineRegistrationCodec.text(writer, 1, request.authSessionId);
        writer.field(2, LineCompactType.STRUCT, 1);
        LineRegistrationCodec.text(writer, 1, request.device.udid);
        LineRegistrationCodec.text(writer, 2, request.device.deviceModel, 1);
        writer.byte(LineCompactType.STOP);
        writer.field(3, LineCompactType.STRUCT, 2);
        LineRegistrationCodec.phone(writer, request.userPhoneNumber);
      });
  }

  static phoneRequest(method: string, request: LineRegistrationPhoneRequest, sequence: number,
    tail?: (writer: LineCompactWriter) => void): Uint8Array {
    return LineRegistrationCodec.request(method, sequence, (writer: LineCompactWriter): void => {
      LineRegistrationCodec.text(writer, 1, request.authSessionId);
      writer.field(2, LineCompactType.STRUCT, 1);
      LineRegistrationCodec.phone(writer, request.userPhoneNumber);
      tail?.(writer);
    });
  }

  static requestCode(request: LineRegistrationCodeRequest, sequence: number): Uint8Array {
    return LineRegistrationCodec.phoneRequest(LineRegistrationRpcMethod.REQUEST_CODE, request, sequence,
      (writer: LineCompactWriter): void => {
        writer.field(3, LineCompactType.I32, 2);
        writer.integer(request.verifMethod);
      });
  }

  static verify(request: LineRegistrationVerifyRequest, sequence: number): Uint8Array {
    return LineRegistrationCodec.phoneRequest(LineRegistrationRpcMethod.VERIFY_CODE, request, sequence,
      (writer: LineCompactWriter): void => { LineRegistrationCodec.text(writer, 3, request.pinCode, 2); });
  }

  static profile(request: LineRegistrationProfileRequest, sequence: number): Uint8Array {
    return LineRegistrationCodec.request(LineRegistrationRpcMethod.VALIDATE_PROFILE, sequence, (writer: LineCompactWriter): void => {
      LineRegistrationCodec.text(writer, 1, request.authSessionId);
      LineRegistrationCodec.text(writer, 2, request.displayName, 1);
    }, false);
  }

  static password(request: LineRegistrationPasswordRequest, sequence: number): Uint8Array {
    return LineRegistrationCodec.request(LineRegistrationRpcMethod.SET_PASSWORD, sequence, (writer: LineCompactWriter): void => {
      LineRegistrationCodec.text(writer, 1, request.authSessionId);
      LineRegistrationCodec.text(writer, 2, request.password, 1);
    });
  }

  static session(method: string, session: string, sequence: number, create: boolean = false): Uint8Array {
    return LineRegistrationCodec.request(method, sequence, (writer: LineCompactWriter): void => {
      LineRegistrationCodec.text(writer, create ? 2 : 1, session);
    }, !create);
  }

  static empty(reader: LineCompactReader): void {
    reader.struct((): boolean => false);
  }

  /** Validate the full envelope before raising declared service errors. */
  static response<T>(bytes: Uint8Array, method: string, sequence: number, successType: LineCompactType,
    parse: (reader: LineCompactReader) => T, talk: boolean = false, voidResult: boolean = false): T {
    if (bytes.length > LineCompactLimits.MESSAGE_BYTES) { throw lineRegistrationInvalid(); }
    const reader = new LineCompactReader(bytes, lineRegistrationInvalid);
    if (reader.byte() !== LineCompactMessage.PROTOCOL_ID) { throw lineRegistrationInvalid(); }
    const versionType: number = reader.byte();
    if ((versionType & LineCompactMessage.VERSION_MASK) !== LineCompactMessage.VERSION ||
      reader.uint() !== sequence || reader.string() !== method) { throw lineRegistrationInvalid(); }
    const messageType: number = versionType >> LineCompactMessage.TYPE_SHIFT;
    if (messageType === LineCompactMessage.EXCEPTION) {
      throw new MiniAppError(LineErrorCode.REGISTRATION_APPLICATION_ERROR, 'LINE registration RPC was rejected',
        LineCompactCodec.readApplicationExceptionCause(reader, lineRegistrationInvalid));
    }
    if (messageType !== LineCompactMessage.REPLY) { throw lineRegistrationInvalid(); }
    let result: T | undefined;
    let success: boolean = false;
    let failure: LineRegistrationFailure | undefined;
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      if (id === 0) {
        if (voidResult) { throw lineRegistrationInvalid(); }
        LineRegistrationReaders.expect(type, successType);
        result = parse(reader);
        success = true;
        return true;
      }
      if (id === 1) {
        LineRegistrationReaders.expect(type, LineCompactType.STRUCT);
        failure = talk ? LineRegistrationReaders.readTalkFailure(reader) : LineRegistrationReaders.readAuthFailure(reader);
        return true;
      }
      return false;
    });
    if (!reader.finished() || (success && failure !== undefined) ||
      (!voidResult && !success && failure === undefined)) { throw lineRegistrationInvalid(); }
    if (failure !== undefined) { throw new LineRegistrationError(failure, talk ? 'talk' : 'registration'); }
    return result as T;
  }

  static passwordParameters(reader: LineCompactReader): LineRegistrationPasswordResponse {
    const params: PasswordParametersWire = {};
    let rules: LinePasswordRule[] | undefined;
    LineRegistrationReaders.struct(reader, (id: number, type: number): boolean => {
      if (id === 1) {
        LineRegistrationReaders.expect(type, LineCompactType.STRUCT);
        LineRegistrationReaders.struct(reader, (field: number, kind: number): boolean => {
          if (field === 1) {
            LineRegistrationReaders.expect(kind, LineCompactType.BINARY);
            params.hmacKey = reader.string(); return true;
          }
          if (field !== 2) { return false; }
          LineRegistrationReaders.expect(kind, LineCompactType.STRUCT);
          LineRegistrationReaders.struct(reader, (key: number, wire: number): boolean => {
            if (key === 1 || key === 2) {
              LineRegistrationReaders.expect(wire, LineCompactType.BINARY);
              if (key === 1) { params.salt = reader.string(); } else { params.nrp = reader.string(); }
              return true;
            }
            if (key === 3) {
              LineRegistrationReaders.expect(wire, LineCompactType.I64);
              params.dkLen = reader.long(); return true;
            }
            return false;
          });
          return true;
        });
        return true;
      }
      if (id !== 2) { return false; }
      LineRegistrationReaders.expect(type, LineCompactType.LIST);
      const count: number = reader.listCount(LineCompactType.STRUCT);
      rules = [];
      for (let index: number = 0; index < count; index++) {
        let ruleType: number | undefined;
        const rule: LinePasswordRule = { patterns: [], message: '' };
        LineRegistrationReaders.struct(reader, (key: number, wire: number): boolean => {
          if (key === 1) {
            LineRegistrationReaders.expect(wire, LineCompactType.I32);
            ruleType = reader.integer(); return true;
          }
          if (key === 2) {
            LineRegistrationReaders.expect(wire, LineCompactType.LIST);
            rule.patterns = reader.strings(); return true;
          }
          if (key === 3) {
            LineRegistrationReaders.expect(wire, LineCompactType.BINARY);
            rule.message = reader.string(); return true;
          }
          return false;
        });
        if (ruleType !== 0) {
          throw new MiniAppError(LineErrorCode.REGISTRATION_RULE_UNSUPPORTED, 'Unsupported LINE registration password rule');
        }
        rules.push(rule);
      }
      return true;
    });
    if (params.hmacKey === undefined || params.salt === undefined || params.nrp === undefined ||
      params.dkLen === undefined || rules === undefined) { throw lineRegistrationInvalid(); }
    const normalized: LinePasswordHashParameters = {
      hmacKey: params.hmacKey, salt: params.salt, nrp: params.nrp, dkLen: params.dkLen
    };
    return { params: normalized, rules };
  }
}
