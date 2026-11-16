import {
  LineCompactMessage,
  LineCompactType,
  LineRpcField,
  LineTokenRefreshRpcMethod
} from '../network/LineRpcConstants';
import { LineErrorCode } from '../LineErrorCode';
import { MiniAppError } from '../../../core/MiniAppError';
import {
  LineCompactCodec,
  LineCompactReader as Reader,
  LineCompactWriter as Writer
} from '../network/LineCompactCodec';
import { LineRefreshTokenResult } from './LineAccountTypes';

/** refresh 请求、结果和 AccessTokenRefreshException 的 wire 字段，分别属于独立结构。 */
enum RefreshRequestField {
  REFRESH_TOKEN = 1
}

/** ReportRefreshedAccessTokenRequest，与 RefreshRequest 是独立结构。 */
enum ReportRequestField {
  ACCESS_TOKEN = 1
}

enum RefreshResultField {
  ACCESS_TOKEN = 1,
  REFRESH_AFTER_SEC = 2,
  RETRY_POLICY = 3,
  REFRESH_TOKEN = 5
}

enum RefreshErrorField {
  ERROR_CODE = 1,
  REASON_CODE = 2
}

function invalid(): MiniAppError {
  return new MiniAppError(LineErrorCode.QR_PROTOCOL_ERROR, 'LINE Token 维护协议格式无效');
}

/** 仅处理刷新服务的请求与异常结构，不依赖扫码协议。 */
export class LineTokenRefreshCodec {
  static encodeRefreshToken(refreshToken: string, sequence: number): Uint8Array {
    return LineTokenRefreshCodec.encodeTokenRequest(LineTokenRefreshRpcMethod.REFRESH,
      RefreshRequestField.REFRESH_TOKEN, refreshToken, sequence);
  }

  static encodeReportRefreshedAccessToken(accessToken: string, sequence: number): Uint8Array {
    return LineTokenRefreshCodec.encodeTokenRequest(LineTokenRefreshRpcMethod.REPORT,
      ReportRequestField.ACCESS_TOKEN, accessToken, sequence);
  }

  static decodeReportRefreshedAccessToken(bytes: Uint8Array, sequence: number): void {
    // APK u05/f 的 success=0 是空的 u05/k STRUCT，并非没有 success 字段的 void 结果。
    LineTokenRefreshCodec.response(bytes, LineTokenRefreshRpcMethod.REPORT, sequence, (reader: Reader): void => {
      reader.struct((): boolean => false);
    });
  }

  static decodeRefreshToken(bytes: Uint8Array, sequence: number): LineRefreshTokenResult {
    let accessToken: string = '';
    let refreshToken: string | undefined;
    let durationUntilRefreshInSec: number = 0;
    let hasRetryPolicy: boolean = false;
    LineTokenRefreshCodec.response(bytes, LineTokenRefreshRpcMethod.REFRESH, sequence, (reader: Reader): void => {
      reader.struct((id: number, type: number): boolean => {
        if (id === RefreshResultField.ACCESS_TOKEN && type === LineCompactType.BINARY) {
          accessToken = reader.string();
          return true;
        }
        if (id === RefreshResultField.REFRESH_AFTER_SEC && type === LineCompactType.I64) {
          durationUntilRefreshInSec = reader.long();
          return true;
        }
        if (id === RefreshResultField.RETRY_POLICY && type === LineCompactType.STRUCT) {
          reader.struct((): boolean => false);
          hasRetryPolicy = true;
          return true;
        }
        if (id === RefreshResultField.REFRESH_TOKEN && type === LineCompactType.BINARY) {
          refreshToken = reader.string();
          return true;
        }
        return false;
      });
    });
    if (!accessToken || durationUntilRefreshInSec <= 0 || !hasRetryPolicy) {
      throw invalid();
    }
    return { accessToken, refreshToken, durationUntilRefreshInSec };
  }

  private static encodeTokenRequest(method: string, field: number, token: string, sequence: number): Uint8Array {
    if (!token || !Number.isInteger(sequence) || sequence < 0) {
      throw invalid();
    }
    const writer = new Writer();
    writer.byte(LineCompactMessage.PROTOCOL_ID);
    writer.byte(LineCompactMessage.CALL_HEADER);
    writer.uint(sequence);
    writer.string(method);
    writer.field(LineRpcField.REQUEST, LineCompactType.STRUCT);
    writer.field(field, LineCompactType.BINARY);
    writer.string(token);
    writer.byte(LineCompactType.STOP);
    writer.byte(LineCompactType.STOP);
    return writer.result();
  }

  private static response(bytes: Uint8Array, method: string, sequence: number,
    parseSuccess: (reader: Reader) => void): void {
    let code: number | undefined;
    let reason: number | undefined;
    const success = LineCompactCodec.response(bytes, method, sequence, parseSuccess, (reader: Reader): void => {
      reader.struct((id: number, type: number): boolean => {
        if (id === RefreshErrorField.ERROR_CODE) {
          if (type !== LineCompactType.I32 || code !== undefined) {
            throw invalid();
          }
          code = reader.integer();
          return true;
        }
        if (id === RefreshErrorField.REASON_CODE) {
          if (type !== LineCompactType.I64 || reason !== undefined) {
            throw invalid();
          }
          reason = reader.long();
          return true;
        }
        return false;
      });
    });
    if (!success) {
      if (code === undefined) {
        throw invalid();
      }
      throw new MiniAppError(LineErrorCode.tokenRefresh(code, reason), 'LINE 账号刷新被拒绝');
    }
  }
}
