import {
  LineCompactLimits,
  LineCompactMessage,
  LineCompactType,
  LineLiffRpcMethod,
  LineRpcField
} from '../network/LineRpcConstants';
import {
  LineCompactCodec,
  LineCompactReader as CompactReader,
  LineCompactWriter as CompactWriter
} from '../network/LineCompactCodec';
import { LineErrorCode, LineServiceErrorCode } from '../LineErrorCode';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineLiffViewResult, LineSubViewRequest, LineSubWindowResultRequest } from './LineLiffTypes';
import { LineConsentRequiredError } from './LineConsentRequiredError';
import { LineSubViewCloseButtonPosition, LineSubViewPresentationType } from './LineSubViewPresentation';

/** APK SubWindowResultRequest 的字段；不是发行请求中的 MSIT 字段。 */
enum SubWindowResultField {
  MSIT = 1,
  MST_VERIFIER = 2
}

/** 主/子视图共享的发行请求结构；MSIT 只用于子窗口，其他可选字段编号不能顺移。 */
enum LiffRequestField {
  LIFF_ID = 1,
  CONTEXT = 2,
  MSIT = 5,
  SUBSEQUENT_LIFF = 6,
  DOMAIN = 7,
  INTER_WINDOW_SESSION = 8,
  URL = 9
}

enum LiffContextField {
  NONE = 1
}

enum LiffResultField {
  VIEW = 1,
  CONTEXT_TOKEN = 2,
  ACCESS_TOKEN = 3,
  FEATURE_TOKEN = 4,
  CLIENT_ID = 6,
  ID_TOKEN = 7,
  SCOPES = 8,
  LAUNCH_OPTIONS = 9,
  SUBVIEW = 11,
  LIFF_ID = 15
}

enum LiffViewField {
  TYPE = 1,
  URL = 2
}

enum LiffSubViewField {
  PRESENTATION_TYPE = 1,
  URL = 2,
  CLOSE_BUTTON_POSITION = 5,
  CLOSE_BUTTON_LABEL = 6,
  HIDE_CLOSE_BUTTON = 9
}

enum LiffServiceErrorField {
  ERROR_CODE = 1,
  PAYLOAD = 3
}

/** nf0/x 是 union，consentRequired 的 field ID 为 3，不是异常 code 的位置。 */
enum LiffErrorPayloadField {
  CONSENT_REQUIRED = 3
}

enum LiffConsentField {
  CHANNEL_ID = 1,
  CONSENT_URL = 2
}

interface LiffConsentPayload {
  channelId?: string;
  consentUrl?: string;
}

/** 服务端 launchOptions 的枚举值，不是字段编号或 Compact 类型。 */
enum LiffLaunchOption {
  DIRECT_LINK_V1 = 1,
  DIRECT_LINK_V2 = 2
}

function invalid(): MiniAppError {
  return new MiniAppError(LineErrorCode.RPC_PROTOCOL_ERROR, 'LINE 子视图响应格式无效');
}

export class LineSubViewCodec {
  static encodeMain(liffId: string, requestedUrl: string, domain: string, sequence: number): Uint8Array {
    if (!liffId || !requestedUrl || !domain) {
      throw invalid();
    }
    const writer = new CompactWriter();
    writer.byte(LineCompactMessage.PROTOCOL_ID);
    writer.byte(LineCompactMessage.CALL_HEADER);
    writer.uint(sequence);
    writer.string(LineLiffRpcMethod.ISSUE_VIEW);
    writer.field(LineRpcField.REQUEST, LineCompactType.STRUCT);
    writer.field(LiffRequestField.LIFF_ID, LineCompactType.BINARY);
    writer.string(liffId);
    writer.field(LiffRequestField.CONTEXT, LineCompactType.STRUCT, LiffRequestField.LIFF_ID);
    writer.field(LiffContextField.NONE, LineCompactType.STRUCT);
    writer.byte(LineCompactType.STOP);
    writer.byte(LineCompactType.STOP); // context.none
    writer.field(LiffRequestField.SUBSEQUENT_LIFF, LineCompactType.BOOLEAN_FALSE, LiffRequestField.CONTEXT);
    writer.field(LiffRequestField.DOMAIN, LineCompactType.BINARY, LiffRequestField.SUBSEQUENT_LIFF);
    writer.string(domain); // field 7
    writer.field(LiffRequestField.URL, LineCompactType.BINARY, LiffRequestField.DOMAIN);
    writer.string(requestedUrl); // field 9
    writer.byte(LineCompactType.STOP);
    writer.byte(LineCompactType.STOP);
    return writer.result();
  }

  static encode(request: LineSubViewRequest, sequence: number): Uint8Array {
    const writer = new CompactWriter();
    writer.byte(LineCompactMessage.PROTOCOL_ID);
    writer.byte(LineCompactMessage.CALL_HEADER);
    writer.uint(sequence);
    writer.string(LineLiffRpcMethod.ISSUE_SUB_VIEW);
    writer.field(LineRpcField.REQUEST, LineCompactType.STRUCT);
    writer.field(LiffRequestField.LIFF_ID, LineCompactType.BINARY);
    writer.string(request.liffId);
    writer.field(LiffRequestField.CONTEXT, LineCompactType.STRUCT, LiffRequestField.LIFF_ID);
    writer.field(LiffContextField.NONE, LineCompactType.STRUCT);
    writer.byte(LineCompactType.STOP);
    writer.byte(LineCompactType.STOP); // context.none
    writer.field(LiffRequestField.MSIT, LineCompactType.BINARY, LiffRequestField.CONTEXT);
    writer.string(request.msit);
    writer.field(LiffRequestField.SUBSEQUENT_LIFF, LineCompactType.BOOLEAN_FALSE, LiffRequestField.MSIT);
    let previous: number = LiffRequestField.SUBSEQUENT_LIFF;
    if (request.domain !== undefined) {
      writer.field(LiffRequestField.DOMAIN, LineCompactType.BINARY, LiffRequestField.SUBSEQUENT_LIFF);
      writer.string(request.domain);
      previous = LiffRequestField.DOMAIN;
    }
    if (request.interWindowSession !== undefined) {
      writer.field(LiffRequestField.INTER_WINDOW_SESSION, LineCompactType.BINARY, previous);
      writer.string(request.interWindowSession);
      previous = LiffRequestField.INTER_WINDOW_SESSION;
    }
    writer.field(LiffRequestField.URL, LineCompactType.BINARY, previous);
    writer.string(request.requestedUrl);
    writer.byte(LineCompactType.STOP);
    writer.byte(LineCompactType.STOP);
    return writer.result();
  }

  static encodeStoreResult(request: LineSubWindowResultRequest, sequence: number): Uint8Array {
    const writer = new CompactWriter();
    writer.byte(LineCompactMessage.PROTOCOL_ID);
    writer.byte(LineCompactMessage.CALL_HEADER);
    writer.uint(sequence);
    writer.string(LineLiffRpcMethod.STORE_SUB_WINDOW_RESULT);
    writer.field(LineRpcField.REQUEST, LineCompactType.STRUCT);
    writer.field(SubWindowResultField.MSIT, LineCompactType.BINARY);
    writer.string(request.msit);
    writer.field(SubWindowResultField.MST_VERIFIER, LineCompactType.BINARY, SubWindowResultField.MSIT);
    writer.string(request.mstVerifier);
    writer.byte(LineCompactType.STOP);
    writer.byte(LineCompactType.STOP);
    return writer.result();
  }

  static decode(bytes: Uint8Array, sequence: number,
    method: string = LineLiffRpcMethod.ISSUE_SUB_VIEW): LineLiffViewResult {
    const result: LineLiffViewResult | undefined = LineSubViewCodec.readReply(bytes, sequence, method, true);
    if (!result) {
      throw invalid();
    }
    return result;
  }

  static decodeStoreResult(bytes: Uint8Array, sequence: number): void {
    LineSubViewCodec.readReply(bytes, sequence, LineLiffRpcMethod.STORE_SUB_WINDOW_RESULT, false);
  }

  /** void 收尾只要求完整空 result；与发行共享 envelope、异常和 consent 校验。 */
  private static readReply(bytes: Uint8Array, sequence: number, method: string,
    expectView: boolean): LineLiffViewResult | undefined {
    if (bytes.length > LineCompactLimits.MESSAGE_BYTES) {
      throw invalid();
    }
    const reader = new CompactReader(bytes, invalid);
    if (reader.byte() !== LineCompactMessage.PROTOCOL_ID) {
      throw invalid();
    }
    const versionType = reader.byte();
    if ((versionType & LineCompactMessage.VERSION_MASK) !== LineCompactMessage.VERSION || reader.uint() !== sequence ||
      reader.string() !== method) {
      throw invalid();
    }
    if ((versionType >> LineCompactMessage.TYPE_SHIFT) === LineCompactMessage.EXCEPTION) {
      throw new MiniAppError(LineErrorCode.RPC_APPLICATION_ERROR, 'LINE RPC 拒绝请求',
        LineCompactCodec.readApplicationExceptionCause(reader, invalid));
    }
    if ((versionType >> LineCompactMessage.TYPE_SHIFT) !== LineCompactMessage.REPLY) {
      throw invalid();
    }
    let result: LineLiffViewResult | undefined;
    let failure: MiniAppError | undefined;
    reader.struct((id: number, type: number): boolean => {
      // void 没有 success 字段，已知异常不能因类型错误被跳过并误判为空成功。
      if (!expectView && (id === LineRpcField.ERROR || id === LineRpcField.ACCOUNT_ERROR) &&
        type !== LineCompactType.STRUCT) {
        throw invalid();
      }
      if (type !== LineCompactType.STRUCT) {
        return false;
      }
      if (expectView && id === LineRpcField.SUCCESS) {
        result = LineSubViewCodec.readView(reader);
        return true;
      }
      if (id === LineRpcField.ERROR || id === LineRpcField.ACCOUNT_ERROR) {
        let code: number = 0;
        let consent: LiffConsentPayload | undefined;
        reader.struct((field: number, fieldType: number): boolean => {
          if (field === LiffServiceErrorField.ERROR_CODE && fieldType === LineCompactType.I32) {
            code = reader.integer();
            return true;
          }
          if (id === LineRpcField.ERROR && field === LiffServiceErrorField.PAYLOAD &&
            fieldType === LineCompactType.STRUCT) {
            consent = LineSubViewCodec.readErrorPayload(reader);
            return true;
          }
          return false;
        });
        if (id === LineRpcField.ERROR && code === LineServiceErrorCode.LIFF_CONSENT_REQUIRED) {
          // APK 仅要求 consentUrl；LIFF_CHANNEL 页面不要求额外的 channelId 参数。
          failure = consent?.consentUrl ?
            new LineConsentRequiredError(consent.channelId, consent.consentUrl) :
            new MiniAppError(LineErrorCode.liffService(code), 'LINE 小程序需要用户同意授权');
        } else {
          failure = new MiniAppError(id === LineRpcField.ERROR ? LineErrorCode.liffService(code) :
            LineErrorCode.accountService(code), 'LINE 服务拒绝视图请求');
        }
        return true;
      }
      return false;
    });
    if (!reader.finished()) {
      throw invalid();
    }
    if (result) {
      return result;
    }
    if (failure) {
      throw failure;
    }
    return undefined;
  }

  /** 只读取已确认的 union 分支；未知字段仍由 CompactReader 按 wire type 跳过。 */
  private static readErrorPayload(reader: CompactReader): LiffConsentPayload | undefined {
    let consent: LiffConsentPayload | undefined;
    reader.struct((id: number, type: number): boolean => {
      if (id !== LiffErrorPayloadField.CONSENT_REQUIRED || type !== LineCompactType.STRUCT) {
        return false;
      }
      const value: LiffConsentPayload = {};
      reader.struct((field: number, fieldType: number): boolean => {
        if (fieldType !== LineCompactType.BINARY) {
          return false;
        }
        if (field === LiffConsentField.CHANNEL_ID) {
          value.channelId = reader.string();
          return true;
        }
        if (field === LiffConsentField.CONSENT_URL) {
          value.consentUrl = reader.string();
          return true;
        }
        return false;
      });
      consent = value;
      return true;
    });
    return consent;
  }

  private static readView(reader: CompactReader): LineLiffViewResult {
    const result: LineLiffViewResult = { url: '' };
    let subUrl: string | undefined;
    reader.struct((id: number, type: number): boolean => {
      if (id === LiffResultField.VIEW && type === LineCompactType.STRUCT) {
        reader.struct((field: number, fieldType: number): boolean => {
          if (field === LiffViewField.TYPE) {
            if (fieldType !== LineCompactType.BINARY) {
              throw invalid();
            }
            result.viewType = reader.string();
            return true;
          }
          if (field === LiffViewField.URL && fieldType === LineCompactType.BINARY) {
            result.url = reader.string();
            return true;
          }
          return false;
        });
        return true;
      }
      if (id === LiffResultField.SUBVIEW && type === LineCompactType.STRUCT) {
        reader.struct((field: number, fieldType: number): boolean => {
          if (field === LiffSubViewField.PRESENTATION_TYPE && fieldType === LineCompactType.I32) {
            const value: number = reader.integer();
            switch (value) {
              case LineSubViewPresentationType.FULL:
                result.presentationType = LineSubViewPresentationType.FULL;
                break;
              case LineSubViewPresentationType.TALL:
                result.presentationType = LineSubViewPresentationType.TALL;
                break;
              case LineSubViewPresentationType.COMPACT:
                result.presentationType = LineSubViewPresentationType.COMPACT;
                break;
              default:
                result.presentationType = undefined;
            }
            return true;
          }
          if (field === LiffSubViewField.URL && fieldType === LineCompactType.BINARY) {
            subUrl = reader.string();
            return true;
          }
          if (field === LiffSubViewField.CLOSE_BUTTON_POSITION && fieldType === LineCompactType.I32) {
            const value: number = reader.integer();
            switch (value) {
              case LineSubViewCloseButtonPosition.RIGHT:
                result.closeButtonPosition = LineSubViewCloseButtonPosition.RIGHT;
                break;
              case LineSubViewCloseButtonPosition.LEFT:
                result.closeButtonPosition = LineSubViewCloseButtonPosition.LEFT;
                break;
              default:
                result.closeButtonPosition = undefined;
            }
            return true;
          }
          if (field === LiffSubViewField.CLOSE_BUTTON_LABEL && fieldType === LineCompactType.BINARY) {
            result.closeButtonLabel = reader.string();
            return true;
          }
          if (field === LiffSubViewField.HIDE_CLOSE_BUTTON &&
            (fieldType === LineCompactType.BOOLEAN_TRUE || fieldType === LineCompactType.BOOLEAN_FALSE)) {
            result.hideCloseButton = fieldType === LineCompactType.BOOLEAN_TRUE;
            return true;
          }
          return false;
        });
        return true;
      }
      if (id === LiffResultField.SCOPES && type === LineCompactType.LIST) {
        result.scopes = reader.strings();
        return true;
      }
      if (id === LiffResultField.LAUNCH_OPTIONS && type === LineCompactType.LIST) {
        const options: number[] = reader.integers();
        result.directLinkV1 = options.indexOf(LiffLaunchOption.DIRECT_LINK_V1) >= 0;
        result.directLinkV2 = options.indexOf(LiffLaunchOption.DIRECT_LINK_V2) >= 0;
        return true;
      }
      if (type !== LineCompactType.BINARY) {
        return false;
      }
      switch (id) {
        case LiffResultField.CONTEXT_TOKEN:
          result.contextToken = reader.string();
          return true;
        case LiffResultField.ACCESS_TOKEN:
          result.accessToken = reader.string();
          return true;
        case LiffResultField.FEATURE_TOKEN:
          result.featureToken = reader.string();
          return true;
        case LiffResultField.CLIENT_ID:
          result.clientId = reader.string();
          return true;
        case LiffResultField.ID_TOKEN:
          result.idToken = reader.string();
          return true;
        case LiffResultField.LIFF_ID:
          result.liffId = reader.string();
          return true;
        default:
          return false;
      }
    });
    if (subUrl !== undefined) {
      result.url = subUrl;
    }
    return result;
  }
}
