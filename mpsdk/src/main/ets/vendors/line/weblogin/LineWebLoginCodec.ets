import { MiniAppError } from '../../../core/MiniAppError';
import { LineErrorCode, LineServiceErrorCode } from '../LineErrorCode';
import { LineCompactCodec, LineCompactReader, LineCompactWriter } from '../network/LineCompactCodec';
import {
  LineCompactLimits, LineCompactMessage, LineCompactType, LineRpcField, LineWebLoginRpcMethod
} from '../network/LineRpcConstants';
import { LineWebLoginInput, LineWebLoginResult, LineWebLoginSource } from './LineWebLoginTypes';

/** nf0/q1、gp8/zq 的共有字段；字段 3 随服务为 context 或 fromIAB。 */
enum RequestField {
  URL = 1,
  SESSION = 2,
  CONTEXT_OR_IAB = 3
}

enum ResponseField {
  URL = 1,
  SESSION = 2,
  LIFF_ID = 3
}
/** nf0/q 与 gp8/z4：结构相同，错误码来源仍分别保留。 */
enum ErrorField {
  CODE = 1,
  MESSAGE = 2,
  PAYLOAD_OR_PARAMETERS = 3
}

enum LiffExceptionField {
  LIFF = 1,
  CHANNEL = 2,
  TALK = 3
}

enum ConsentField {
  PAYLOAD_BRANCH = 3,
  CHANNEL_ID = 1,
  URL = 2
}
const CHANNEL_PERMISSION_REQUIRED: number = 4;
const NONE_CONTEXT_FIELD: number = 1;
const CONSENT_URL_KEY: string = 'consentUrl';
const SESSION_KEY: string = 'sessionString';

function invalid(): MiniAppError {
  return new MiniAppError(LineErrorCode.WEB_LOGIN_PROTOCOL_INVALID, 'Invalid LINE web login response');
}

/** WebLogin 自己的 args/result；不依赖视图发行解码器。 */
export class LineWebLoginCodec {
  static method(source: LineWebLoginSource, allowed: boolean): string {
    if (source === 'browser') {
      return allowed ? LineWebLoginRpcMethod.BROWSER_RETURN : LineWebLoginRpcMethod.BROWSER_DISALLOWED;
    }
    return allowed ? LineWebLoginRpcMethod.LIFF_RETURN : LineWebLoginRpcMethod.LIFF_DISALLOWED;
  }

  static encode(source: LineWebLoginSource, input: LineWebLoginInput,
    allowed: boolean, sequence: number): Uint8Array {
    const writer = new LineCompactWriter();
    writer.byte(LineCompactMessage.PROTOCOL_ID);
    writer.byte(LineCompactMessage.CALL_HEADER);
    writer.uint(sequence);
    writer.string(LineWebLoginCodec.method(source, allowed));
    writer.field(LineRpcField.REQUEST, LineCompactType.STRUCT);
    writer.field(RequestField.URL, LineCompactType.BINARY);
    writer.string(input.hookedFullUrl);
    let previous: number = RequestField.URL;
    if (input.sessionString !== undefined) {
      writer.field(RequestField.SESSION, LineCompactType.BINARY, previous);
      writer.string(input.sessionString);
      previous = RequestField.SESSION;
    }
    if (source === 'browser') {
      writer.field(RequestField.CONTEXT_OR_IAB, LineCompactType.BOOLEAN_TRUE, previous);
    } else {
      writer.field(RequestField.CONTEXT_OR_IAB, LineCompactType.STRUCT, previous);
      writer.field(NONE_CONTEXT_FIELD, LineCompactType.STRUCT);
      writer.byte(LineCompactType.STOP);
      writer.byte(LineCompactType.STOP);
    }
    writer.byte(LineCompactType.STOP);
    writer.byte(LineCompactType.STOP);
    return writer.result();
  }

  static decode(source: LineWebLoginSource, bytes: Uint8Array,
    allowed: boolean, sequence: number): LineWebLoginResult {
    if (bytes.length > LineCompactLimits.MESSAGE_BYTES) {
      throw invalid();
    }
    const reader = new LineCompactReader(bytes, invalid);
    if (reader.byte() !== LineCompactMessage.PROTOCOL_ID) {
      throw invalid();
    }
    const header = reader.byte();
    if ((header & LineCompactMessage.VERSION_MASK) !== LineCompactMessage.VERSION ||
      reader.uint() !== sequence || reader.string() !== LineWebLoginCodec.method(source, allowed)) {
      throw invalid();
    }
    const messageType: number = header >> LineCompactMessage.TYPE_SHIFT;
    if (messageType === LineCompactMessage.EXCEPTION) {
      throw new MiniAppError(LineErrorCode.RPC_APPLICATION_ERROR, 'LINE rejected web login',
        LineCompactCodec.readApplicationExceptionCause(reader, invalid));
    }
    if (messageType !== LineCompactMessage.REPLY) {
      throw invalid();
    }
    let result: LineWebLoginResult | undefined;
    let failure: MiniAppError | undefined;
    let seen: boolean = false;
    reader.struct((id: number, type: number): boolean => {
      const last: number = source === 'browser' ? LineRpcField.ERROR : LiffExceptionField.TALK;
      if (id < LineRpcField.SUCCESS || id > last) {
        return false;
      }
      if (seen || type !== LineCompactType.STRUCT) {
        throw invalid();
      }
      seen = true;
      if (id === LineRpcField.SUCCESS) {
        result = LineWebLoginCodec.readSuccess(reader, source);
      } else {
        const exception = LineWebLoginCodec.readFailure(reader, source, id);
        result = exception.result;
        failure = exception.failure;
      }
      return true;
    });
    if (!reader.finished() || !seen) {
      throw invalid();
    }
    if (failure) {
      throw failure;
    }
    if (!result || (!result.returnUrl && !result.consentUrl) || (result.returnUrl && result.consentUrl)) {
      throw invalid();
    }
    return result;
  }

  private static readSuccess(reader: LineCompactReader, source: LineWebLoginSource): LineWebLoginResult {
    const result: LineWebLoginResult = {};
    const seen = new Set<number>();
    reader.struct((id: number, type: number): boolean => {
      if (id < ResponseField.URL || id > ResponseField.LIFF_ID) {
        return false;
      }
      if (type !== LineCompactType.BINARY || seen.has(id)) {
        throw invalid();
      }
      seen.add(id);
      const value = reader.string();
      if (id === ResponseField.URL) {
        result.returnUrl = value;
      } else if (source !== 'browser') {
        if (id === ResponseField.SESSION) {
          result.sessionString = value;
        } else {
          result.liffId = value;
        }
      }
      // gp8/ar 的 2/3 是 optionalReturnUrl / redirectConfirmationPageUrl，APK 本分支不用。
      return true;
    });
    return result;
  }

  private static readFailure(reader: LineCompactReader, source: LineWebLoginSource,
    exceptionId: number): WebLoginFailure {
    const channel: boolean = source === 'browser' || exceptionId === LiffExceptionField.CHANNEL;
    const liff: boolean = !channel && exceptionId === LiffExceptionField.LIFF;
    let code: number | undefined;
    let parameters = new Map<string, string>();
    let consentUrl: string | undefined;
    const seen = new Set<number>();
    reader.struct((id: number, type: number): boolean => {
      if (id < ErrorField.CODE || id > ErrorField.PAYLOAD_OR_PARAMETERS) {
        return false;
      }
      if (seen.has(id)) {
        throw invalid();
      }
      seen.add(id);
      if (id === ErrorField.CODE) {
        if (type !== LineCompactType.I32) {
          throw invalid();
        }
        code = reader.integer();
      } else if (id === ErrorField.MESSAGE) {
        if (type !== LineCompactType.BINARY) {
          throw invalid();
        }
        reader.string();
      } else if (liff) {
        if (type !== LineCompactType.STRUCT) {
          throw invalid();
        }
        consentUrl = LineWebLoginCodec.readConsent(reader);
      } else {
        if (type !== LineCompactType.MAP) {
          throw invalid();
        }
        parameters = reader.stringMap();
      }
      return true;
    });
    if (code === undefined) {
      throw invalid();
    }
    if (channel && code === CHANNEL_PERMISSION_REQUIRED) {
      const address = parameters.get(CONSENT_URL_KEY);
      if (!address) {
        throw invalid();
      }
      return { result: { consentUrl: address, sessionString: parameters.get(SESSION_KEY) } };
    }
    if (liff && code === LineServiceErrorCode.LIFF_CONSENT_REQUIRED && consentUrl) {
      return { result: { consentUrl } };
    }
    return { failure: new MiniAppError(channel ? LineErrorCode.channelService(code) :
      liff ? LineErrorCode.liffService(code) : LineErrorCode.accountService(code), 'LINE rejected web login') };
  }

  private static readConsent(reader: LineCompactReader): string | undefined {
    let address: string | undefined;
    let seenBranch: boolean = false;
    reader.struct((id: number, type: number): boolean => {
      if (id !== ConsentField.PAYLOAD_BRANCH) {
        return false;
      }
      if (type !== LineCompactType.STRUCT || seenBranch) {
        throw invalid();
      }
      seenBranch = true;
      const seen = new Set<number>();
      reader.struct((field: number, fieldType: number): boolean => {
        if (field !== ConsentField.CHANNEL_ID && field !== ConsentField.URL) {
          return false;
        }
        if (fieldType !== LineCompactType.BINARY || seen.has(field)) {
          throw invalid();
        }
        seen.add(field);
        const value = reader.string();
        if (field === ConsentField.URL) {
          address = value;
        }
        return true;
      });
      return true;
    });
    return address;
  }
}

interface WebLoginFailure {
  result?: LineWebLoginResult;
  failure?: MiniAppError;
}
