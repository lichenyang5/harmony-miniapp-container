/**
 * LINE 稳定错误标识的唯一来源。字符串值属于现有宿主/网页契约，不因重构改名。
 * 这里只定义标识，不统一错误文案、异常原文或日志载荷。
 * 动态数字码由服务端提供，工厂保留未知码，不能视为本地错误枚举已穷尽。
 */
export class LineErrorCode {
  static readonly REGISTRATION_FAILED: string = 'LINE_REGISTRATION_FAILED';
  static readonly REGISTRATION_CANCELLED: string = 'LINE_REGISTRATION_CANCELLED';
  static readonly REGISTRATION_INVALID_STATE: string = 'LINE_REGISTRATION_INVALID_STATE';
  static readonly REGISTRATION_UNSUPPORTED: string = 'LINE_REGISTRATION_UNSUPPORTED';
  static readonly REGISTRATION_NOT_ALLOWED: string = 'LINE_REGISTRATION_NOT_ALLOWED';
  static readonly REGISTRATION_ACCOUNT_CONFLICT: string = 'LINE_REGISTRATION_ACCOUNT_CONFLICT';
  static readonly REGISTRATION_INCOMPLETE: string = 'LINE_REGISTRATION_INCOMPLETE';
  static readonly REGISTRATION_CREATION_UNCERTAIN: string = 'LINE_REGISTRATION_CREATION_UNCERTAIN';
  static readonly REGISTRATION_CRYPTO_FAILED: string = 'LINE_REGISTRATION_CRYPTO_FAILED';
  static readonly REGISTRATION_PASSWORD_INVALID: string = 'LINE_REGISTRATION_PASSWORD_INVALID';
  static readonly REGISTRATION_DEVICE_FAILED: string = 'LINE_REGISTRATION_DEVICE_FAILED';

  /** 注册协议与服务错误；wire 数字码保留在内部 LineRegistrationError。 */
  static readonly REGISTRATION_PROTOCOL_ERROR: string = 'LINE_REGISTRATION_PROTOCOL_ERROR';
  static readonly REGISTRATION_APPLICATION_ERROR: string = 'LINE_REGISTRATION_APPLICATION_ERROR';
  static readonly REGISTRATION_REJECTED: string = 'LINE_REGISTRATION_REJECTED';
  static readonly REGISTRATION_INTERNAL_ERROR: string = 'LINE_REGISTRATION_INTERNAL_ERROR';
  static readonly REGISTRATION_ILLEGAL_ARGUMENT: string = 'LINE_REGISTRATION_ILLEGAL_ARGUMENT';
  static readonly REGISTRATION_VERIFICATION_FAILED: string = 'LINE_REGISTRATION_VERIFICATION_FAILED';
  static readonly REGISTRATION_NOT_FOUND: string = 'LINE_REGISTRATION_NOT_FOUND';
  static readonly REGISTRATION_RETRY_LATER: string = 'LINE_REGISTRATION_RETRY_LATER';
  static readonly REGISTRATION_HUMAN_VERIFICATION_REQUIRED: string = 'LINE_REGISTRATION_HUMAN_VERIFICATION_REQUIRED';
  static readonly REGISTRATION_INVALID_CONTEXT: string = 'LINE_REGISTRATION_INVALID_CONTEXT';
  static readonly REGISTRATION_APP_UPGRADE_REQUIRED: string = 'LINE_REGISTRATION_APP_UPGRADE_REQUIRED';
  static readonly REGISTRATION_TALK_REJECTED: string = 'LINE_REGISTRATION_TALK_REJECTED';
  static readonly REGISTRATION_TOKEN_REFRESH_REQUIRED: string = 'LINE_REGISTRATION_TOKEN_REFRESH_REQUIRED';
  static readonly REGISTRATION_RULE_UNSUPPORTED: string = 'LINE_REGISTRATION_RULE_UNSUPPORTED';
  /** 有效 Retry-After 期间抑制同 host 后续请求，不自动重试。 */
  static readonly RPC_RETRY_LATER: string = 'LINE_RPC_RETRY_LATER';
  /** Mini App 入口地址无效。 */
  static readonly ENTRY_INVALID: string = 'LINE_ENTRY_INVALID';
  /** Mini App 引导页解析或网络请求失败。 */
  static readonly ENTRY_RESOLVE_FAILED: string = 'LINE_ENTRY_RESOLVE_FAILED';
  /** 仅支持官方 HTTPS MINI App 域名的有效 Custom Path。 */
  static readonly CUSTOM_PATH_INVALID: string = 'LINE_CUSTOM_PATH_INVALID';
  /** 官方入口明确返回不存在。 */
  static readonly CUSTOM_PATH_NOT_FOUND: string = 'LINE_CUSTOM_PATH_NOT_FOUND';
  /** 官方入口请求或网络失败。 */
  static readonly CUSTOM_PATH_RESOLVE_FAILED: string = 'LINE_CUSTOM_PATH_RESOLVE_FAILED';
  /** 官方入口页面已不包含可核验的客户端 LIFF ID。 */
  static readonly CUSTOM_PATH_RESPONSE_INVALID: string = 'LINE_CUSTOM_PATH_RESPONSE_INVALID';
  /** 官方网页 OAuth 转原生授权失败，不影响已登录账号。 */
  static readonly WEB_LOGIN_FAILED: string = 'LINE_WEB_LOGIN_FAILED';
  /** WebLogin 方法自己的 wire schema 校验失败。 */
  static readonly WEB_LOGIN_PROTOCOL_INVALID: string = 'LINE_WEB_LOGIN_PROTOCOL_INVALID';
  /** 同一授权要求重复出现且会话没有推进。 */
  static readonly WEB_LOGIN_NO_PROGRESS: string = 'LINE_WEB_LOGIN_NO_PROGRESS';
  /** QRCodeReader 导航扫码、结果展示、复制或打开操作失败。 */
  static readonly QR_READER_FAILED: string = 'LINE_QR_READER_FAILED';
  /** 页面直接进入 LIFF HTTP(S) 地址时，宿主无法接受目标小程序的打开请求。 */
  static readonly DIRECT_NAVIGATION_FAILED: string = 'LINE_DIRECT_NAVIGATION_FAILED';
  /** 内置普通浏览器的展示、关闭或资源释放失败。 */
  static readonly BROWSER_FAILED: string = 'LINE_BROWSER_FAILED';
  /** 用户拒绝授权、返回或所属视图取消等待；不会退出已认证的 LINE 账号。 */
  static readonly CONSENT_CANCELLED: string = 'LINE_CONSENT_CANCELLED';
  /** 官方授权页面地址不满足凭据加载规则。 */
  static readonly CONSENT_INVALID: string = 'LINE_CONSENT_INVALID';
  /** 官方授权弹层创建、加载或关闭失败。 */
  static readonly CONSENT_UI_FAILED: string = 'LINE_CONSENT_UI_FAILED';
  /** 当前会话已有一个授权弹层，不能覆盖原请求。 */
  static readonly CONSENT_BUSY: string = 'LINE_CONSENT_BUSY';
  /** 尚未实现的客户端网页认证模式，不允许静默降级。 */
  static readonly MODE_NOT_SUPPORTED: string = 'LINE_MODE_NOT_SUPPORTED';
  /** 原生登录弹层创建、展示或关闭失败。 */
  static readonly LOGIN_UI_FAILED: string = 'LINE_LOGIN_UI_FAILED';
  /** 邮箱密码必须是非空字符串，且符合 RSA 单次认证载荷大小。 */
  static readonly EMAIL_INVALID_ARGUMENT: string = 'LINE_EMAIL_INVALID_ARGUMENT';
  /** 邮箱认证协议格式错误，不暴露服务端载荷。 */
  static readonly EMAIL_PROTOCOL_ERROR: string = 'LINE_EMAIL_PROTOCOL_ERROR';
  /** AuthService 返回 Thrift application exception，私有提示只存入 originalCause。 */
  static readonly EMAIL_APPLICATION_ERROR: string = 'LINE_EMAIL_APPLICATION_ERROR';
  /** 邮箱密码认证失败的边界兜底。 */
  static readonly EMAIL_LOGIN_FAILED: string = 'LINE_EMAIL_LOGIN_FAILED';
  /** 邮箱认证加密或密钥转换失败。 */
  static readonly EMAIL_CRYPTO_FAILED: string = 'LINE_EMAIL_CRYPTO_FAILED';
  /** 主设备验证等待超时，需用户主动重试。 */
  static readonly EMAIL_VERIFICATION_TIMEOUT: string = 'LINE_EMAIL_VERIFICATION_TIMEOUT';
  /** 主设备取消认证。 */
  static readonly EMAIL_VERIFICATION_REJECTED: string = 'LINE_EMAIL_VERIFICATION_REJECTED';
  /** 服务端要求切换扫码或短信认证，邮箱流程不能伪造完成。 */
  static readonly EMAIL_VERIFICATION_UNSUPPORTED: string = 'LINE_EMAIL_VERIFICATION_UNSUPPORTED';
  /** APK TalkException 119：必须刷新 V3 Token；LIFF 仅据此触发一次刷新重试。 */
  static readonly ACCOUNT_MUST_REFRESH: string = 'LINE_ACCOUNT_ERROR_119';
  /** 请配置 LINE 子视图授权来源。 */
  static readonly ACCOUNT_PROVIDER_REQUIRED: string = 'LINE_ACCOUNT_PROVIDER_REQUIRED';
  /** LINE 账号恢复失败。 */
  static readonly ACCOUNT_RESTORE_FAILED: string = 'LINE_ACCOUNT_RESTORE_FAILED';
  /** LINE 持久化未启用。 */
  static readonly ACCOUNT_STORAGE_DISABLED: string = 'LINE_ACCOUNT_STORAGE_DISABLED';
  /** 持久化失败的兼容标识；当前内部存储仅记录失败日志，不改变成功登录结果。 */
  static readonly ACCOUNT_STORAGE_FAILED: string = 'LINE_ACCOUNT_STORAGE_FAILED';
  /** 导航拒绝诊断：LIFF 地址或参数无效。 */
  static readonly APP_INVALID_ARGUMENT: string = 'LINE_APP_INVALID_ARGUMENT';
  /** 导航拒绝诊断：子框架不得发起顶层 LIFF 应用切换。 */
  static readonly APP_SUBFRAME: string = 'LINE_APP_SUBFRAME';
  /** 导航拒绝诊断：当前容器不支持切换到其他 LIFF ID。 */
  static readonly APP_SWITCH_NOT_SUPPORTED: string = 'LINE_APP_SWITCH_NOT_SUPPORTED';
  /** 原生 LINE Bridge 异常包装；网页实际回包码由 LineBridgeErrorCode 定义。 */
  static readonly BRIDGE_ERROR: string = 'LINE_BRIDGE_ERROR';
  /** 连接信息、客户端标识或请求头配置无效；不得用猜测端点或身份继续请求。 */
  static readonly CONNECTION_CONFIG_REQUIRED: string = 'LINE_CONNECTION_CONFIG_REQUIRED';
  /** LINE 连接信息请求失败。 */
  static readonly CONN_INFO_HTTP_FAILED: string = 'LINE_CONN_INFO_HTTP_FAILED';
  /** LINE 连接信息格式无效。 */
  static readonly CONN_INFO_INVALID: string = 'LINE_CONN_INFO_INVALID';
  /** 无法展示 LINE 子窗口。 */
  static readonly DIALOG_FAILED: string = 'LINE_DIALOG_FAILED';
  /** LINE 视图发行失败。 */
  static readonly LIFF_FAILED: string = 'LINE_LIFF_FAILED';
  /** LINE 账号已切换。 */
  static readonly LOGIN_CANCELLED: string = 'LINE_LOGIN_CANCELLED';
  /** LINE 扫码登录失败。 */
  static readonly LOGIN_FAILED: string = 'LINE_LOGIN_FAILED';
  /** 等待 PIN 确认阶段发生未分类异常。 */
  static readonly LOGIN_FAILED_CHECK_PIN_CODE: string = 'LINE_LOGIN_FAILED_CHECK_PIN_CODE';
  /** 等待扫码确认阶段发生未分类异常。 */
  static readonly LOGIN_FAILED_CHECK_QR_CODE: string = 'LINE_LOGIN_FAILED_CHECK_QR_CODE';
  /** 创建 PIN 阶段发生未分类异常。 */
  static readonly LOGIN_FAILED_CREATE_PIN_CODE: string = 'LINE_LOGIN_FAILED_CREATE_PIN_CODE';
  /** 创建安全二维码阶段发生未分类异常。 */
  static readonly LOGIN_FAILED_CREATE_QR_CODE: string = 'LINE_LOGIN_FAILED_CREATE_QR_CODE';
  /** 创建扫码会话阶段发生未分类异常。 */
  static readonly LOGIN_FAILED_CREATE_SESSION: string = 'LINE_LOGIN_FAILED_CREATE_SESSION';
  /** 最终扫码登录阶段发生未分类异常。 */
  static readonly LOGIN_FAILED_QR_CODE_LOGIN: string = 'LINE_LOGIN_FAILED_QR_CODE_LOGIN';
  /** 证书校验响应解码失败。 */
  static readonly LOGIN_FAILED_VERIFY_CERTIFICATE_DECODE: string = 'LINE_LOGIN_FAILED_VERIFY_CERTIFICATE_DECODE';
  /** 证书校验请求编码失败。 */
  static readonly LOGIN_FAILED_VERIFY_CERTIFICATE_ENCODE: string = 'LINE_LOGIN_FAILED_VERIFY_CERTIFICATE_ENCODE';
  /** 证书校验请求发送失败。 */
  static readonly LOGIN_FAILED_VERIFY_CERTIFICATE_SEND: string = 'LINE_LOGIN_FAILED_VERIFY_CERTIFICATE_SEND';
  /** LINE 登录缺少设备信息。 */
  static readonly LOGIN_INVALID_DEVICE: string = 'LINE_LOGIN_INVALID_DEVICE';
  /** LINE 登录正在进行。 */
  static readonly LOGIN_IN_PROGRESS: string = 'LINE_LOGIN_IN_PROGRESS';
  /** 无法生成 LINE 安全二维码密钥。 */
  static readonly LOGIN_KEY_FAILED: string = 'LINE_LOGIN_KEY_FAILED';
  /** LINE 二维码密钥参数无效。 */
  static readonly LOGIN_KEY_INVALID: string = 'LINE_LOGIN_KEY_INVALID';
  /** LINE 账号未登录或凭据已过期。 */
  static readonly LOGIN_REQUIRED: string = 'LINE_LOGIN_REQUIRED';
  /** LINE 主视图需要 V1 直链初始化。 */
  static readonly MAINVIEW_DIRECT_LINK_V1_UNSUPPORTED: string = 'LINE_MAINVIEW_DIRECT_LINK_V1_UNSUPPORTED';
  /** LINE 主视图请求地址无效。 */
  static readonly MAINVIEW_INVALID: string = 'LINE_MAINVIEW_INVALID';
  /** LINE 主视图缺少会话挑战。 */
  static readonly MST_REQUIRED: string = 'LINE_MST_REQUIRED';
  /** 网页警告标识：无法写入 MST 会话存储；不是服务端账号错误。 */
  static readonly MST_STORAGE_UNAVAILABLE: string = 'LINE_MST_STORAGE_UNAVAILABLE';
  /** LINE RPC 请求被拒绝。 */
  static readonly QR_APPLICATION_ERROR: string = 'LINE_QR_APPLICATION_ERROR';
  /** LINE 扫码确认超时。 */
  static readonly QR_CONFIRM_TIMEOUT: string = 'LINE_QR_CONFIRM_TIMEOUT';
  /** LINE 安全二维码版本不兼容。 */
  static readonly QR_E2EE_INVALID_VERSION: string = 'LINE_QR_E2EE_INVALID_VERSION';
  /** LINE 扫码确认失败。 */
  static readonly QR_POLL_FAILED: string = 'LINE_QR_POLL_FAILED';
  /** 长轮询本地超时；扫码流程按服务端次数限制决定是否继续轮询。 */
  static readonly QR_POLL_TIMEOUT: string = 'LINE_QR_POLL_TIMEOUT';
  /** LINE 扫码登录响应格式无效。 */
  static readonly QR_PROTOCOL_ERROR: string = 'LINE_QR_PROTOCOL_ERROR';
  /** 扫码服务异常的兜底码；有服务端数字码时使用 qrService()。 */
  static readonly QR_SERVICE_ERROR: string = 'LINE_QR_SERVICE_ERROR';
  /** LINE RPC 拒绝请求。 */
  static readonly RPC_APPLICATION_ERROR: string = 'LINE_RPC_APPLICATION_ERROR';
  /** LINE 服务请求失败。 */
  static readonly RPC_HTTP_FAILED: string = 'LINE_RPC_HTTP_FAILED';
  /** LINE 网络请求失败。 */
  static readonly RPC_NETWORK_FAILED: string = 'LINE_RPC_NETWORK_FAILED';
  /** LINE 子视图响应格式无效。 */
  static readonly RPC_PROTOCOL_ERROR: string = 'LINE_RPC_PROTOCOL_ERROR';
  /** 非轮询 RPC 超过本地等待期限。 */
  static readonly RPC_TIMEOUT: string = 'LINE_RPC_TIMEOUT';
  /** LINE 会话已关闭。 */
  static readonly SESSION_CLOSED: string = 'LINE_SESSION_CLOSED';
  /** 申请 LINE 子视图失败。 */
  static readonly SUBVIEW_FAILED: string = 'LINE_SUBVIEW_FAILED';
  /** LINE 子视图授权字段无效。 */
  static readonly SUBVIEW_INVALID: string = 'LINE_SUBVIEW_INVALID';
  /** 申请 LINE 子视图超时。 */
  static readonly SUBVIEW_TIMEOUT: string = 'LINE_SUBVIEW_TIMEOUT';
  /** 已有 LINE 子窗口正在打开或运行。 */
  static readonly SUBWINDOW_BUSY: string = 'LINE_SUBWINDOW_BUSY';
  /** 原生子窗口结果收尾失败；窗口关闭不等待该异步操作。 */
  static readonly SUBWINDOW_CLOSE_FAILED: string = 'LINE_SUBWINDOW_CLOSE_FAILED';
  /** LINE 子窗口被系统关闭。 */
  static readonly SUBWINDOW_DISMISSED: string = 'LINE_SUBWINDOW_DISMISSED';
  /** 打开 LINE 子窗口失败。 */
  static readonly SUBWINDOW_FAILED: string = 'LINE_SUBWINDOW_FAILED';
  /** LINE 子窗口地址或参数无效。 */
  static readonly SUBWINDOW_INVALID: string = 'LINE_SUBWINDOW_INVALID';
  /** LINE 账号刷新失败。 */
  static readonly TOKEN_REFRESH_FAILED: string = 'LINE_TOKEN_REFRESH_FAILED';
  /** LINE 子窗口视图尚未绑定。 */
  static readonly WINDOW_HOST_REQUIRED: string = 'LINE_WINDOW_HOST_REQUIRED';

  /** SecondaryQrCodeException：数字码沿用 APK；无数字码时保持旧兜底码。 */
  static qrService(code: number): string {
    return code >= 0 ? `LINE_QR_SERVICE_ERROR_${code}` : LineErrorCode.QR_SERVICE_ERROR;
  }

  /** AccessTokenRefreshException：errorCode 与可选 reasonCode 均保留数值语义。 */
  static tokenRefresh(code: number, reason?: number): string {
    return `LINE_TOKEN_REFRESH_ERROR_${code}${reason === undefined ? '' : `_REASON_${reason}`}`;
  }

  /** AuthService TalkException 数字码；保留未知码，不携带服务端私有文案。 */
  static emailService(code: number): string {
    return `LINE_EMAIL_SERVICE_ERROR_${code}`;
  }

  /** 刷新请求已被明确拒绝，需要重新登录；不将网络失败或未知服务码当作账号失效。 */
  static isTokenRefreshRejected(code: string): boolean {
    const rejected: string = LineErrorCode.tokenRefresh(LineServiceErrorCode.REFRESH_INVALID_REQUEST);
    return code === rejected || code.startsWith(`${rejected}_REASON_`);
  }

  /** LIFF 业务异常与账号 TalkException 使用不同前缀，不能混为同一来源。 */
  static liffService(code: number): string {
    return `LINE_LIFF_ERROR_${code}`;
  }

  static accountService(code: number): string {
    return `LINE_ACCOUNT_ERROR_${code}`;
  }

  /** ChannelService 与 LIFF、Talk 数字码分开。 */
  static channelService(code: number): string {
    return `LINE_CHANNEL_ERROR_${code}`;
  }

  /** 仅用于原生诊断入口识别扫码服务异常，不放宽其他来源的消息展示。 */
  static isQrService(code: string): boolean {
    return /^LINE_QR_SERVICE_ERROR_\d+$/.test(code);
  }

  /** 原生诊断仅保留平台数字码，不把原始平台消息或业务参数带入日志。 */
  static nativeDiagnostic(code: number): string {
    return `NATIVE_${code}`;
  }
}

/** LINE 网页 Bridge 回包错误码，包含原生 Bridge 与 LIFF 标准错误；与 SDK 的 LINE_* 异常码分开。 */
export class LineBridgeErrorCode {
  /** featureToken 与当前应用配置不匹配。 */
  static readonly NO_AUTHORITY: string = 'NO_AUTHORITY';
  /** 方法存在，但当前应用未获得使用权限。 */
  static readonly PERMISSION_DENIED: string = 'PERMISSION_DENIED';
  /** 未识别的方法或消息类型。 */
  static readonly INVALID_MESSAGE: string = 'INVALID_MESSAGE';
  /** 打开入口拒绝参数或无法接受目标。 */
  static readonly INVALID_ARGUMENT: string = 'INVALID_ARGUMENT';
  /** LIFF 官方错误码：没有使用当前 API 的权限或当前运行环境不支持。 */
  static readonly FORBIDDEN: string = 'FORBIDDEN';
  /** SDK 防御性兜底；不携带原始异常或堆栈。 */
  static readonly INTERNAL_ERROR: string = 'INTERNAL_ERROR';
  /** 未细分的 LIFF 客户端异常，例如用户取消原生扫码。 */
  static readonly UNKNOWN: string = 'UNKNOWN';
}

/** APK 各服务异常的数字码；按服务区分，不能与本地错误字符串互换。 */
export class LineServiceErrorCode {
  /** APK nf0/u.CONSENT_REQUIRED：当前小程序需要用户同意授权，区别于账号未登录。 */
  static readonly LIFF_CONSENT_REQUIRED: number = 3;
  /** APK gp8/m9.INVALID_IDENTITY_CREDENTIAL，真实 wire value 为 18。 */
  static readonly EMAIL_INVALID_IDENTITY_CREDENTIAL: number = 18;
  /** APK gp8/m9.NOT_ALLOWED_SECONDARY_DEVICE；wire value 为 44，不是 enum ordinal 43。 */
  static readonly EMAIL_NOT_ALLOWED_SECONDARY_DEVICE: number = 44;
  /** SecondaryQrCodeException：主设备未允许副设备登录。 */
  static readonly QR_NOT_ALLOWED_SECONDARY_DEVICE: number = 3;
  /** APK AuthService 仅对此码重新尝试无 E2EE 认证；其它拒绝不得降级。 */
  static readonly EMAIL_E2EE_SENDER_NOT_ALLOWED: number = 89;
  /** verifyCertificate 的 VERIFICATION_FAILED 表示需要走 PIN，不代表最终登录失败。 */
  static readonly CERTIFICATE_VERIFICATION_FAILED: number = 2;
  /** AccessTokenRefreshException.INVALID_REQUEST；不解释 reasonCode 的未知细分含义。 */
  static readonly REFRESH_INVALID_REQUEST: number = 1000;
}
