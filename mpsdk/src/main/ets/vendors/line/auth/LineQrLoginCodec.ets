import { LineCompactMessage, LineCompactType, LineRpcField } from '../network/LineRpcConstants';
import { LineErrorCode, LineServiceErrorCode } from '../LineErrorCode';
import { MiniAppError } from '../../../core/MiniAppError';
import {
  LineCompactCodec,
  LineCompactReader as Reader,
  LineCompactWriter as Writer
} from '../network/LineCompactCodec';
import { LineAccountCredential, LineQrCodeResponse, LineQrLoginRequest } from './LineAccountTypes';

/** 各枚举对应独立 Thrift struct；编号沿用 APK wire schema，不能因字段省略重新排序。 */
enum QrSessionField {
  AUTH_SESSION_ID = 1
}

enum QrCertificateField {
  AUTH_SESSION_ID = 1,
  CERTIFICATE = 2
}

enum QrLoginRequestField {
  AUTH_SESSION_ID = 1,
  SYSTEM_NAME = 2,
  MODEL_NAME = 3,
  AUTO_LOGIN = 4,
  NONCE = 5
}

enum QrCodeResultField {
  CALLBACK_URL = 1,
  POLLING_MAX_COUNT = 2,
  POLLING_INTERVAL_SEC = 3,
  NONCE = 4
}

enum QrPinResultField {
  PIN = 1
}

enum QrLoginResultField {
  CERTIFICATE = 1,
  V3_TOKEN = 3,
  MID = 4,
  METADATA = 10
}

/** V3 Token 嵌套结构；与刷新服务响应的字段编号不同。 */
enum QrV3TokenField {
  ACCESS_TOKEN = 1,
  REFRESH_TOKEN = 2,
  REFRESH_AFTER_SEC = 3,
  RETRY_POLICY = 4,
  LOGIN_SESSION_ID = 5
}

enum QrServiceErrorField {
  ERROR_CODE = 1,
  ALERT_MESSAGE = 2
}

function invalid(): MiniAppError {
  return new MiniAppError(LineErrorCode.QR_PROTOCOL_ERROR, 'LINE 扫码登录响应格式无效');
}

export class LineQrLoginCodec {
  static encodeCreateSession(sequence: number): Uint8Array {
    return LineQrLoginCodec.request('createSession', sequence);
  }

  static encodeCreateQrCode(sessionId: string, sequence: number): Uint8Array {
    return LineQrLoginCodec.request('createQrCodeForSecure', sequence, sessionId);
  }

  static encodeCheckQrCodeVerified(sessionId: string, sequence: number): Uint8Array {
    return LineQrLoginCodec.request('checkQrCodeVerified', sequence, sessionId);
  }

  static encodeCreatePinCode(sessionId: string, sequence: number): Uint8Array {
    return LineQrLoginCodec.request('createPinCode', sequence, sessionId);
  }

  static encodeCheckPinCodeVerified(sessionId: string, sequence: number): Uint8Array {
    return LineQrLoginCodec.request('checkPinCodeVerified', sequence, sessionId);
  }

  static encodeVerifyCertificate(sessionId: string, certificate: string, sequence: number): Uint8Array {
    if (!Number.isInteger(sequence) || sequence < 0 || !sessionId ||
      typeof certificate !== 'string') {
      throw invalid();
    }
    const writer = new Writer();
    writer.byte(LineCompactMessage.PROTOCOL_ID);
    writer.byte(LineCompactMessage.CALL_HEADER);
    writer.uint(sequence);
    writer.string('verifyCertificate');
    writer.field(LineRpcField.REQUEST, LineCompactType.STRUCT);
    writer.field(QrCertificateField.AUTH_SESSION_ID, LineCompactType.BINARY);
    writer.string(sessionId);
    writer.field(QrCertificateField.CERTIFICATE, LineCompactType.BINARY, QrCertificateField.AUTH_SESSION_ID);
    writer.string(certificate);
    writer.byte(LineCompactType.STOP);
    writer.byte(LineCompactType.STOP);
    return writer.result();
  }

  static encodeQrCodeLogin(request: LineQrLoginRequest, sequence: number): Uint8Array {
    if (!Number.isInteger(sequence) || sequence < 0 || !request.authSessionId ||
      !request.systemName || !request.modelName || !request.nonce ||
      typeof request.autoLoginIsRequired !== 'boolean') {
      throw invalid();
    }
    const writer = new Writer();
    writer.byte(LineCompactMessage.PROTOCOL_ID);
    writer.byte(LineCompactMessage.CALL_HEADER);
    writer.uint(sequence);
    writer.string('qrCodeLoginV2ForSecure');
    writer.field(LineRpcField.REQUEST, LineCompactType.STRUCT);
    writer.field(QrLoginRequestField.AUTH_SESSION_ID, LineCompactType.BINARY);
    writer.string(request.authSessionId);
    writer.field(QrLoginRequestField.SYSTEM_NAME, LineCompactType.BINARY, QrLoginRequestField.AUTH_SESSION_ID);
    writer.string(request.systemName);
    writer.field(QrLoginRequestField.MODEL_NAME, LineCompactType.BINARY, QrLoginRequestField.SYSTEM_NAME);
    writer.string(request.modelName);
    writer.field(QrLoginRequestField.AUTO_LOGIN, request.autoLoginIsRequired ?
      LineCompactType.BOOLEAN_TRUE : LineCompactType.BOOLEAN_FALSE, QrLoginRequestField.MODEL_NAME);
    writer.field(QrLoginRequestField.NONCE, LineCompactType.BINARY, QrLoginRequestField.AUTO_LOGIN);
    writer.string(request.nonce);
    writer.byte(LineCompactType.STOP);
    writer.byte(LineCompactType.STOP);
    return writer.result();
  }

  static decodeCreateSession(bytes: Uint8Array, sequence: number): string {
    let sessionId: string = '';
    LineQrLoginCodec.response(bytes, 'createSession', sequence, (reader: Reader): void => {
      reader.struct((id: number, type: number): boolean => {
        if (id === QrSessionField.AUTH_SESSION_ID && type === LineCompactType.BINARY) {
          sessionId = reader.string();
          return true;
        }
        return false;
      });
    });
    if (!sessionId) {
      throw invalid();
    }
    return sessionId;
  }

  static decodeCreateQrCode(bytes: Uint8Array, sequence: number): LineQrCodeResponse {
    const result: LineQrCodeResponse = {
      callbackUrl: '',
      longPollingMaxCount: 0,
      longPollingIntervalSec: 0,
      nonce: ''
    };
    LineQrLoginCodec.response(bytes, 'createQrCodeForSecure', sequence, (reader: Reader): void => {
      reader.struct((id: number, type: number): boolean => {
        if (id === QrCodeResultField.CALLBACK_URL && type === LineCompactType.BINARY) {
          result.callbackUrl = reader.string();
          return true;
        }
        if (id === QrCodeResultField.POLLING_MAX_COUNT && type === LineCompactType.I32) {
          result.longPollingMaxCount = reader.integer();
          return true;
        }
        if (id === QrCodeResultField.POLLING_INTERVAL_SEC && type === LineCompactType.I32) {
          result.longPollingIntervalSec = reader.integer();
          return true;
        }
        if (id === QrCodeResultField.NONCE && type === LineCompactType.BINARY) {
          result.nonce = reader.string();
          return true;
        }
        return false;
      });
    });
    if (!result.callbackUrl || !result.nonce || result.longPollingMaxCount <= 0 ||
      result.longPollingIntervalSec < 0) {
      throw invalid();
    }
    return result;
  }

  static decodeCheckQrCodeVerified(bytes: Uint8Array, sequence: number): boolean {
    LineQrLoginCodec.response(bytes, 'checkQrCodeVerified', sequence, (reader: Reader): void => {
      reader.struct((): boolean => false);
    });
    return true;
  }

  static decodeCreatePinCode(bytes: Uint8Array, sequence: number): string {
    let pin: string = '';
    LineQrLoginCodec.response(bytes, 'createPinCode', sequence, (reader: Reader): void => {
      reader.struct((id: number, type: number): boolean => {
        if (id === QrPinResultField.PIN && type === LineCompactType.BINARY) {
          pin = reader.string();
          return true;
        }
        return false;
      });
    });
    if (!pin) {
      throw invalid();
    }
    return pin;
  }

  static decodeCheckPinCodeVerified(bytes: Uint8Array, sequence: number): boolean {
    LineQrLoginCodec.response(bytes, 'checkPinCodeVerified', sequence, (reader: Reader): void => {
      reader.struct((): boolean => false);
    });
    return true;
  }

  static decodeVerifyCertificate(bytes: Uint8Array, sequence: number): boolean {
    return LineQrLoginCodec.response(bytes, 'verifyCertificate', sequence, (reader: Reader): void => {
      reader.struct((): boolean => false);
    }, true);
  }

  static decodeQrCodeLogin(bytes: Uint8Array, sequence: number): LineAccountCredential {
    let certificate: string = '';
    let mid: string = '';
    let accessToken: string = '';
    let refreshToken: string = '';
    let loginSessionId: string = '';
    let durationUntilRefreshInSec: number = 0;
    let hasRetryPolicy: boolean = false;
    let metaData: Map<string, string> | undefined;
    LineQrLoginCodec.response(bytes, 'qrCodeLoginV2ForSecure', sequence, (reader: Reader): void => {
      reader.struct((id: number, type: number): boolean => {
        if (id === QrLoginResultField.CERTIFICATE && type === LineCompactType.BINARY) {
          certificate = reader.string();
          return true;
        }
        if (id === QrLoginResultField.V3_TOKEN && type === LineCompactType.STRUCT) {
          reader.struct((field: number, fieldType: number): boolean => {
            if (field === QrV3TokenField.ACCESS_TOKEN && fieldType === LineCompactType.BINARY) {
              accessToken = reader.string();
              return true;
            }
            if (field === QrV3TokenField.REFRESH_TOKEN && fieldType === LineCompactType.BINARY) {
              refreshToken = reader.string();
              return true;
            }
            if (field === QrV3TokenField.REFRESH_AFTER_SEC && fieldType === LineCompactType.I64) {
              durationUntilRefreshInSec = reader.long();
              return true;
            }
            if (field === QrV3TokenField.RETRY_POLICY && fieldType === LineCompactType.STRUCT) {
              reader.struct((): boolean => false);
              hasRetryPolicy = true;
              return true;
            }
            if (field === QrV3TokenField.LOGIN_SESSION_ID && fieldType === LineCompactType.BINARY) {
              loginSessionId = reader.string();
              return true;
            }
            return false;
          });
          return true;
        }
        if (id === QrLoginResultField.MID && type === LineCompactType.BINARY) {
          mid = reader.string();
          return true;
        }
        if (id === QrLoginResultField.METADATA && type === LineCompactType.MAP) {
          metaData = reader.stringMap();
          return true;
        }
        return false;
      });
    });
    if (!certificate || !mid || !accessToken || !refreshToken || !loginSessionId ||
      !hasRetryPolicy || !metaData || durationUntilRefreshInSec <= 0) {
      throw invalid();
    }
    if (metaData.get('errorCode') === 'E2EE_INVALID_VERSION') {
      throw new MiniAppError(LineErrorCode.QR_E2EE_INVALID_VERSION, 'LINE 安全二维码版本不兼容');
    }
    return {
      certificate,
      accessToken,
      refreshToken,
      mid,
      loginSessionId,
      durationUntilRefreshInSec,
      metaData
    };
  }

  private static request(method: string, sequence: number, sessionId?: string): Uint8Array {
    if (!Number.isInteger(sequence) || sequence < 0 || !method ||
      (sessionId !== undefined && !sessionId)) {
      throw invalid();
    }
    const writer = new Writer();
    writer.byte(LineCompactMessage.PROTOCOL_ID);
    writer.byte(LineCompactMessage.CALL_HEADER);
    writer.uint(sequence);
    writer.string(method);
    writer.field(LineRpcField.REQUEST, LineCompactType.STRUCT);
    if (sessionId !== undefined) {
      writer.field(QrSessionField.AUTH_SESSION_ID, LineCompactType.BINARY);
      writer.string(sessionId);
    }
    writer.byte(LineCompactType.STOP);
    writer.byte(LineCompactType.STOP);
    return writer.result();
  }

  private static response(bytes: Uint8Array, method: string, sequence: number,
    parseSuccess: (reader: Reader) => void, allowVerificationFailed: boolean = false): boolean {
    let code: number = -1;
    let alert: string | undefined;
    const success = LineCompactCodec.response(bytes, method, sequence, parseSuccess, (reader: Reader): void => {
      reader.struct((id: number, type: number): boolean => {
        if (id === QrServiceErrorField.ERROR_CODE && type === LineCompactType.I32) {
          code = reader.integer();
          return true;
        }
        if (id === QrServiceErrorField.ALERT_MESSAGE && type === LineCompactType.BINARY) {
          alert = reader.string();
          return true;
        }
        return false;
      });
    });
    if (!success && allowVerificationFailed && code === LineServiceErrorCode.CERTIFICATE_VERIFICATION_FAILED) {
      return false;
    }
    // 原生诊断保留服务提示；公开消息与结构化日志始终使用稳定错误码。
    if (!success) {
      throw new MiniAppError(LineErrorCode.qrService(code),
        'LINE 扫码登录服务拒绝请求', alert === undefined ? undefined : new Error(alert));
    }
    return true;
  }
}
