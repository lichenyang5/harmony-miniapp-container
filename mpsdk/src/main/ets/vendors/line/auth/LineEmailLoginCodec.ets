import { util } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import {
  LineCompactCodec,
  LineCompactReader as Reader,
  LineCompactWriter as Writer
} from '../network/LineCompactCodec';
import {
  LineCompactLimits,
  LineCompactMessage,
  LineCompactType as Type,
  LineRpcField
} from '../network/LineRpcConstants';
import { LINE_X25519_KEY_BYTES, LineAccountCredential } from './LineAccountTypes';
import {
  LINE_EMAIL_AES_BLOCK_BYTES,
  LineEmailLoginRequest,
  LineEmailLoginResult,
  LineEmailLoginType,
  LineEmailResultType,
  LineEmailRsaKey,
  LineEmailVerification
} from './LineEmailLoginTypes';
import { LineErrorCode } from '../LineErrorCode';

/** AuthService LoginRequest；字段 6 未用于此次副设备认证，不能顺移后续字段。 */
enum LoginField {
  TYPE = 1,
  PROVIDER = 2,
  IDENTIFIER = 3,
  PASSWORD = 4,
  KEEP_LOGGED_IN = 5,
  SYSTEM_NAME = 7,
  CERTIFICATE = 8,
  VERIFIER = 9,
  SECRET = 10,
  E2EE_VERSION = 11,
  MODEL_NAME = 12
}

/** AuthService LoginResult，V3 凭据与旧 token 字段独立。 */
enum LoginResultField {
  CERTIFICATE = 2,
  VERIFIER = 3,
  PIN = 4,
  TYPE = 5,
  TOKEN_V3 = 9,
  MID = 10
}

/** LoginResult.tokenV3IssueResult 嵌套 struct。 */
enum TokenField {
  ACCESS = 1,
  REFRESH = 2,
  DURATION = 3,
  SESSION = 5
}

/** RSAKey 响应 struct。 */
enum RsaField {
  KEY_NAME = 1,
  MODULUS = 2,
  EXPONENT = 3,
  SESSION = 4
}

/** getRSAKeyInfo / loginV2 顶层参数均为 2；与扫码服务 REQUEST=1 不同。 */
enum EmailArgument {
  IDENTITY_PROVIDER = 2,
  LOGIN_REQUEST = 2
}

/** confirmE2EELogin 的 RPC 顶层参数，不是 request struct。 */
enum ConfirmArgument {
  VERIFIER = 1,
  HASHED_KEY_CHAIN = 2
}

/** AuthService TalkException struct。 */
enum ServiceErrorField {
  CODE = 1,
  MESSAGE = 2
}

const LINE_IDENTITY_PROVIDER: number = 1;

interface EmailServiceFailure {
  code?: number;
  message?: string;
}

interface VerificationMetadata {
  errorCode?: string;
  publicKey?: string;
  encryptedKeyChain?: string;
}

interface VerificationResult {
  authPhase?: string;
  verifier?: string;
  metadata?: VerificationMetadata;
}

interface VerificationDocument {
  authPhase?: string;
  result?: VerificationResult;
}

function invalid(cause?: Object): MiniAppError {
  return new MiniAppError(LineErrorCode.EMAIL_PROTOCOL_ERROR, 'LINE 邮箱登录响应格式无效', cause);
}

function requireString(value: string | undefined): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw invalid();
  }
  return value;
}

/** AuthService Compact wire 编解码；不负责网络、密码加密、轮询或账号发布。 */
export class LineEmailLoginCodec {
  static encodeRsaKey(sequence: number): Uint8Array {
    const writer = LineEmailLoginCodec.request('getRSAKeyInfo', sequence);
    writer.field(EmailArgument.IDENTITY_PROVIDER, Type.I32);
    writer.integer(LINE_IDENTITY_PROVIDER);
    writer.byte(Type.STOP);
    return writer.result();
  }

  static decodeRsaKey(bytes: Uint8Array, sequence: number): LineEmailRsaKey {
    const result: LineEmailRsaKey = {
      keynm: '',
      nvalue: '',
      evalue: '',
      sessionKey: ''
    };
    const seen: Set<number> = new Set<number>();
    LineEmailLoginCodec.response(bytes, 'getRSAKeyInfo', sequence, Type.STRUCT, (reader: Reader): void => {
      reader.struct((id: number, type: number): boolean => {
        if (type !== Type.BINARY || id < RsaField.KEY_NAME || id > RsaField.SESSION) {
          return false;
        }
        LineEmailLoginCodec.claim(seen, id);
        if (id === RsaField.KEY_NAME) {
          result.keynm = reader.string();
        } else if (id === RsaField.MODULUS) {
          result.nvalue =
            reader.string();
        } else if (id === RsaField.EXPONENT) {
          result.evalue = reader.string();
        } else if (id ===
          RsaField.SESSION) {
          result.sessionKey = reader.string();
        } else {
          return false;
        }
        return true;
      });
    });
    if (!result.keynm || !result.sessionKey || !/^[a-f0-9]+$/i.test(result.nvalue) ||
      !/^[a-f0-9]+$/i.test(result.evalue)) {
      throw invalid();
    }
    return result;
  }

  static encodeLogin(request: LineEmailLoginRequest, sequence: number): Uint8Array {
    if ((request.type !== LineEmailLoginType.ID_CREDENTIAL && request.type !== LineEmailLoginType.QRCODE &&
      request.type !== LineEmailLoginType.ID_CREDENTIAL_WITH_E2EE) ||
      !Number.isInteger(request.e2eeVersion) || request.e2eeVersion < 0 ||
      typeof request.password !== 'string' || !/^(?:[a-f0-9]{2})+$/i.test(request.password) ||
      (request.certificate !== undefined && typeof request.certificate !== 'string') ||
      (request.verifier !== undefined && typeof request.verifier !== 'string') ||
      (request.secret !== undefined &&
        (!(request.secret instanceof Uint8Array) || request.secret.length === 0))) {
      throw invalid();
    }
    requireString(request.keynm);
    requireString(request.systemName);
    requireString(request.modelName);
    const writer = LineEmailLoginCodec.request('loginV2', sequence);
    writer.field(EmailArgument.LOGIN_REQUEST, Type.STRUCT);
    writer.field(LoginField.TYPE, Type.I32);
    writer.integer(request.type);
    writer.field(LoginField.PROVIDER, Type.I32, LoginField.TYPE);
    writer.integer(LINE_IDENTITY_PROVIDER);
    writer.field(LoginField.IDENTIFIER, Type.BINARY, LoginField.PROVIDER);
    writer.string(request.keynm);
    writer.field(LoginField.PASSWORD, Type.BINARY, LoginField.IDENTIFIER);
    writer.string(request.password);
    writer.field(LoginField.KEEP_LOGGED_IN, Type.BOOLEAN_TRUE, LoginField.PASSWORD);
    writer.field(LoginField.SYSTEM_NAME, Type.BINARY, LoginField.KEEP_LOGGED_IN);
    writer.string(request.systemName);
    writer.field(LoginField.CERTIFICATE, Type.BINARY, LoginField.SYSTEM_NAME);
    writer.string(request.certificate ?? '');
    let previous: number = LoginField.CERTIFICATE;
    // 首次认证的 verifier 为 null，APK 不写该字段；验证后才携带服务端 verifier。
    if (request.verifier !== undefined) {
      writer.field(LoginField.VERIFIER, Type.BINARY, previous);
      writer.string(request.verifier);
      previous = LoginField.VERIFIER;
    }
    if (request.secret !== undefined) {
      writer.field(LoginField.SECRET, Type.BINARY, previous);
      LineEmailLoginCodec.binary(writer, request.secret);
      previous = LoginField.SECRET;
    }
    writer.field(LoginField.E2EE_VERSION, Type.I32, previous);
    writer.integer(request.e2eeVersion);
    writer.field(LoginField.MODEL_NAME, Type.BINARY, LoginField.E2EE_VERSION);
    writer.string(request.modelName);
    writer.byte(Type.STOP);
    writer.byte(Type.STOP);
    return writer.result();
  }

  static decodeLogin(bytes: Uint8Array, sequence: number): LineEmailLoginResult {
    const result: LineEmailLoginResult = { type: 0 };
    const credential: LineAccountCredential = {
      certificate: '',
      accessToken: '',
      refreshToken: '',
      mid: '',
      loginSessionId: '',
      durationUntilRefreshInSec: 0,
      metaData: new Map<string, string>()
    };
    const seen: Set<number> = new Set<number>();
    LineEmailLoginCodec.response(bytes, 'loginV2', sequence, Type.STRUCT, (reader: Reader): void => {
      reader.struct((id: number, type: number): boolean => {
        if (id === LoginResultField.TYPE && type === Type.I32) {
          LineEmailLoginCodec.claim(seen, id);
          result.type = reader.integer();
          return true;
        }
        if (id === LoginResultField.TOKEN_V3 && type === Type.STRUCT) {
          LineEmailLoginCodec.claim(seen, id);
          LineEmailLoginCodec.readToken(reader, credential);
          return true;
        }
        if (type !== Type.BINARY) {
          return false;
        }
        switch (id) {
          case LoginResultField.CERTIFICATE:
            LineEmailLoginCodec.claim(seen, id);
            credential.certificate = reader.string();
            break;
          case LoginResultField.MID:
            LineEmailLoginCodec.claim(seen, id);
            credential.mid = reader.string();
            break;
          case LoginResultField.VERIFIER:
            LineEmailLoginCodec.claim(seen, id);
            result.verifier = reader.string();
            break;
          case LoginResultField.PIN:
            LineEmailLoginCodec.claim(seen, id);
            result.pin = reader.string();
            break;
          default:
            return false;
        }
        return true;
      });
    });
    if (result.type === LineEmailResultType.SUCCESS) {
      if (!credential.accessToken || !credential.refreshToken || !credential.mid || !credential.loginSessionId ||
        credential.durationUntilRefreshInSec <= 0) {
        throw invalid();
      }
      result.credential = credential;
    } else if (result.type === LineEmailResultType.QR || result.type === LineEmailResultType.DEVICE ||
      result.type === LineEmailResultType.SMS) {
      requireString(result.verifier);
    } else {
      throw invalid();
    }
    return result;
  }

  static encodeConfirm(verifier: string, proof: Uint8Array, sequence: number): Uint8Array {
    requireString(verifier);
    if (!(proof instanceof Uint8Array) || proof.length === 0) {
      throw invalid();
    }
    const writer = LineEmailLoginCodec.request('confirmE2EELogin', sequence);
    writer.field(ConfirmArgument.VERIFIER, Type.BINARY);
    writer.string(verifier);
    writer.field(ConfirmArgument.HASHED_KEY_CHAIN, Type.BINARY, ConfirmArgument.VERIFIER);
    LineEmailLoginCodec.binary(writer, proof);
    writer.byte(Type.STOP);
    return writer.result();
  }

  static decodeConfirm(bytes: Uint8Array, sequence: number): string {
    let verifier: string = '';
    LineEmailLoginCodec.response(bytes, 'confirmE2EELogin', sequence, Type.BINARY, (reader: Reader): void => {
      verifier = reader.string();
    });
    return requireString(verifier);
  }

  static decodeVerification(bytes: Uint8Array): LineEmailVerification {
    try {
      if (bytes.length > LineCompactLimits.MESSAGE_BYTES) {
        throw invalid();
      }
      const document =
        JSON.parse(util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes)) as VerificationDocument;
      if (!document || typeof document !== 'object' || Array.isArray(document) || !document.result ||
        typeof document.result !== 'object' || Array.isArray(document.result)) {
        throw invalid();
      }
      const result: VerificationResult = document.result;
      const phase: string | undefined = document.authPhase === undefined || document.authPhase === '' ?
        result.authPhase : document.authPhase;
      if (phase === 'QRCODE_VERIFIED') {
        return { kind: 'verifier', verifier: requireString(result.verifier) };
      }
      if (phase !== 'PIN_CODE_DELIVERED' || !result.metadata || typeof result.metadata !== 'object' ||
        Array.isArray(result.metadata)) {
        throw invalid();
      }
      if (result.metadata.errorCode === 'CANCEL') {
        return { kind: 'cancel' };
      }
      if (result.metadata.errorCode !== 'SUCCESS') {
        throw invalid();
      }
      const publicKey = LineEmailLoginCodec.base64(result.metadata.publicKey);
      const encryptedKeyChain = LineEmailLoginCodec.base64(result.metadata.encryptedKeyChain);
      if (publicKey.length !== LINE_X25519_KEY_BYTES || encryptedKeyChain.length === 0 ||
        encryptedKeyChain.length % LINE_EMAIL_AES_BLOCK_BYTES !== 0) {
        throw invalid();
      }
      return { kind: 'e2ee', publicKey, encryptedKeyChain };
    } catch (error) {
      if (error instanceof MiniAppError) {
        throw error;
      }
      throw invalid(error as Object);
    }
  }

  private static base64(value: string | undefined): Uint8Array {
    requireString(value);
    if (value === undefined ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
      throw invalid();
    }
    return new util.Base64Helper().decodeSync(value);
  }

  private static readToken(reader: Reader, credential: LineAccountCredential): void {
    const seen: Set<number> = new Set<number>();
    reader.struct((id: number, type: number): boolean => {
      if (id === TokenField.DURATION && type === Type.I64) {
        LineEmailLoginCodec.claim(seen, id);
        credential.durationUntilRefreshInSec = reader.long();
        return true;
      }
      if (type !== Type.BINARY) {
        return false;
      }
      switch (id) {
        case TokenField.ACCESS:
          LineEmailLoginCodec.claim(seen, id);
          credential.accessToken = reader.string();
          break;
        case TokenField.REFRESH:
          LineEmailLoginCodec.claim(seen, id);
          credential.refreshToken = reader.string();
          break;
        case TokenField.SESSION:
          LineEmailLoginCodec.claim(seen, id);
          credential.loginSessionId = reader.string();
          break;
        default:
          return false;
      }
      return true;
    });
  }

  private static claim(seen: Set<number>, id: number): void {
    if (seen.has(id)) {
      throw invalid();
    }
    seen.add(id);
  }

  private static binary(writer: Writer, bytes: Uint8Array): void {
    writer.uint(bytes.length);
    bytes.forEach((byte: number): void => {
      writer.byte(byte);
    });
  }

  private static request(method: string, sequence: number): Writer {
    if (!Number.isInteger(sequence) || sequence < 0) {
      throw invalid();
    }
    const writer = new Writer();
    writer.byte(LineCompactMessage.PROTOCOL_ID);
    writer.byte(LineCompactMessage.CALL_HEADER);
    writer.uint(sequence);
    writer.string(method);
    return writer;
  }

  /** 成功字段类型随方法变化；完整校验 envelope 后才抛服务错误，防止残包伪装拒绝。 */
  private static response(bytes: Uint8Array, method: string, sequence: number, successType: Type,
    parseSuccess: (reader: Reader) => void): void {
    try {
      if (bytes.length > LineCompactLimits.MESSAGE_BYTES) {
        throw invalid();
      }
      const reader = new Reader(bytes, invalid);
      if (reader.byte() !== LineCompactMessage.PROTOCOL_ID) {
        throw invalid();
      }
      const header = reader.byte();
      if ((header & LineCompactMessage.VERSION_MASK) !== LineCompactMessage.VERSION || reader.uint() !== sequence ||
        reader.string() !== method) {
        throw invalid();
      }
      const messageType: number = header >> LineCompactMessage.TYPE_SHIFT;
      if (messageType !== LineCompactMessage.REPLY && messageType !== LineCompactMessage.EXCEPTION) {
        throw invalid();
      }
      if (messageType === LineCompactMessage.EXCEPTION) {
        throw new MiniAppError(LineErrorCode.EMAIL_APPLICATION_ERROR, 'LINE 邮箱登录请求被拒绝',
          LineCompactCodec.readApplicationExceptionCause(reader, invalid));
      }
      let success: boolean = false;
      let failure: boolean = false;
      const service: EmailServiceFailure = {};
      reader.struct((id: number, type: number): boolean => {
        if (id === LineRpcField.SUCCESS && type === successType) {
          if (success) {
            throw invalid();
          }
          parseSuccess(reader);
          success = true;
          return true;
        }
        if (id === LineRpcField.ERROR && type === Type.STRUCT) {
          if (failure) {
            throw invalid();
          }
          reader.struct((field: number, fieldType: number): boolean => {
            if (field === ServiceErrorField.CODE && fieldType === Type.I32) {
              if (service.code !== undefined) {
                throw invalid();
              }
              service.code = reader.integer();
              return true;
            }
            if (field === ServiceErrorField.MESSAGE && fieldType === Type.BINARY) {
              if (service.message !== undefined) {
                throw invalid();
              }
              service.message = reader.string();
              return true;
            }
            return false;
          });
          failure = true;
          return true;
        }
        return false;
      });
      if (!reader.finished() || success === failure || (failure && service.code === undefined)) {
        throw invalid();
      }
      if (failure && service.code !== undefined) {
        throw new MiniAppError(LineErrorCode.emailService(service.code),
          'LINE 邮箱登录服务拒绝请求',
          service.message === undefined ? undefined : new Error(service.message));
      }
    } catch (error) {
      if (error instanceof MiniAppError) {
        throw error;
      }
      throw invalid(error as Object);
    }
  }
}
