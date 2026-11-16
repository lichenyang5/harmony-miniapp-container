/** 账号 HTTP 请求头；与交付小程序网页的 X-LINE-LIFF-TOKEN 分开。 */
export enum LineAccountHeader {
  ACCESS = 'X-Line-Access',
  APPLICATION = 'X-Line-Application'
}

/** APK RPC 路径。长轮询与普通登录必须走各自路径，不能仅按方法名合并。 */
export enum LineRpcPath {
  LOGIN = '/acct/lgn/sq/v1',
  POLL = '/acct/lp/lgn/sq/v1',
  LIFF = '/LIFF1',
  /** ChannelService：普通内置浏览器网页登录。 */
  CHANNEL = '/CH4',
  REFRESH = '/EXT/auth/tokenrefresh/v1',
  /** 邮箱密码 AuthService：loginV2 / confirmE2EELogin。 */
  AUTH = '/api/v4p/rs',
  /** 邮箱密码 PIN/E2EE 验证等待，返回 JSON；不是扫码的二进制轮询。 */
  EMAIL_VERIFY = '/LF1',
  /** APK 在服务明确不允许 E2EE 后使用普通副设备确认路径。 */
  EMAIL_VERIFY_PLAIN = '/Q',
  /** REGISTRATION TalkService，仅在认证前获取服务器 RSAKey。 */
  IDENTITY = '/api/v4/TalkService.do',
  REGISTRATION = '/acct/pais/v1',
  REGISTRATION_POLL = '/acct/lp/pais/v1',
  ACCOUNT_TALK = '/S4'
}

/** Token 维护服务的方法名；报告当前 Token 与 refresh 使用同一服务。 */
export enum LineTokenRefreshRpcMethod {
  REFRESH = 'refresh',
  REPORT = 'reportRefreshedAccessToken'
}

/** LIFF RPC 方法名；发行和收尾响应按各自结果结构解码。 */
export enum LineLiffRpcMethod {
  ISSUE_VIEW = 'issueLiffView',
  ISSUE_SUB_VIEW = 'issueSubLiffView',
  STORE_SUB_WINDOW_RESULT = 'storeSubWindowResult'
}

export enum LineRegistrationRpcMethod {
  OPEN_SESSION = 'openSession',
  COUNTRY = 'getCountryInfo',
  AVAILABLE_EAP = 'lookupAvailableEap',
  ALLOWED = 'getAllowedRegistrationMethod',
  PHONE_METHODS = 'getPhoneVerifMethodForRegistration',
  REQUEST_CODE = 'requestToSendPhonePinCode',
  VERIFY_CODE = 'verifyPhonePinCode',
  FETCH_SMS = 'fetchPhonePinCodeMsg',
  WAIT_SMS = 'checkIfPhonePinCodeMsgVerified',
  VALIDATE_PROFILE = 'validateProfile',
  PASSWORD_PARAMETERS = 'getPasswordHashingParametersForPwdReg',
  SET_PASSWORD = 'setHashedPassword',
  REGISTER_PHONE = 'registerPrimaryUsingPhoneWithTokenV3'
}

export enum LineRegistrationTalkRpcMethod {
  UPDATE_NAME = 'updateProfileAttributes',
  PROFILE = 'getProfile',
  PENDING_AGREEMENTS = 'getPendingAgreements',
  CONFIGURATIONS = 'getConfigurations',
  SETTINGS = 'getSettings',
  UPDATE_SETTINGS = 'updateSettingsAttributes2'
}

/** WebLogin 两套服务的方法；不能用 LIFF 发行的响应结构解码。 */
export enum LineWebLoginRpcMethod {
  LIFF_RETURN = 'getReturnUrlWithRequestTokenForMultiLiffLogin',
  LIFF_DISALLOWED = 'getWebLoginDisallowedUrlForMultiLiffLogin',
  BROWSER_RETURN = 'getReturnUrlWithRequestTokenForAutoLogin',
  BROWSER_DISALLOWED = 'getWebLoginDisallowedUrl'
}

/** 本地等待策略；不是服务端承诺的超时或凭据有效期。单位均为毫秒。 */
export class LineRpcTimeout {
  static readonly REQUEST_MS: number = 60000;
  static readonly CONNECT_MS: number = 15000;
  static readonly POLL_MS: number = 120000;
  static readonly SUBVIEW_MS: number = 30000;
  static readonly CONN_INFO_MS: number = 10000;
  /** APK PinCodeVerificationNetworkClient 的等待预算。 */
  static readonly EMAIL_VERIFY_MS: number = 180000;
}

/** Compact 防御性解析上限；提取字段和只跳过未知字段使用不同的集合限制。 */
export class LineCompactLimits {
  static readonly MESSAGE_BYTES: number = 4 * 1024 * 1024;
  static readonly NESTING_DEPTH: number = 32;
  static readonly EXTRACTED_ELEMENTS: number = 4096;
  static readonly SKIPPED_ELEMENTS: number = 65536;
}

/** Thrift Compact 消息头，不是业务请求模型的 field ID。 */
export class LineCompactMessage {
  static readonly PROTOCOL_ID: number = 0x82;
  static readonly CALL_HEADER: number = 0x21;
  static readonly VERSION: number = 1;
  static readonly VERSION_MASK: number = 31;
  static readonly TYPE_SHIFT: number = 5;
  static readonly REPLY: number = 2;
  static readonly EXCEPTION: number = 3;
}

/** Thrift Compact wire type；布尔值直接编码在字段头中，BINARY 也用于 UTF-8 字符串。 */
export enum LineCompactType {
  STOP = 0,
  BOOLEAN_TRUE = 1,
  BOOLEAN_FALSE = 2,
  BYTE = 3,
  I16 = 4,
  I32 = 5,
  I64 = 6,
  DOUBLE = 7,
  BINARY = 8,
  LIST = 9,
  SET = 10,
  MAP = 11,
  STRUCT = 12
}

/** 字段头/集合头高四位存增量或长度，低四位存类型；varint 每字节承载七位数据。 */
export class LineCompactEncoding {
  static readonly TYPE_BITS: number = 4;
  static readonly TYPE_MASK: number = 0x0f;
  static readonly INLINE_MAX: number = 15;
  static readonly VARINT_DATA_MASK: number = 0x7f;
  static readonly VARINT_BASE: number = 0x80;
  static readonly VARINT_CONTINUATION: number = 0x80;
  static readonly UINT32_MAX: number = 0xffffffff;
  static readonly UINT32_BYTES: number = 5;
  static readonly INT64_BYTES: number = 10;
  static readonly DOUBLE_BYTES: number = 8;
  static readonly STRING_MAP_TYPES: number =
    (LineCompactType.BINARY << LineCompactEncoding.TYPE_BITS) | LineCompactType.BINARY;
}

/** RPC envelope 字段，不是各业务请求/响应结构中的字段 ID。 */
export enum LineRpcField {
  SUCCESS = 0,
  REQUEST = 1,
  ERROR = 1,
  ACCOUNT_ERROR = 2
}
