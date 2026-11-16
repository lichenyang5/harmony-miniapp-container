/** 单次挂载的选中控制、状态读取及生命周期订阅。 */
export { MiniAppLifecycleController } from './src/main/ets/core/lifecycle/MiniAppLifecycleController';
export { MiniAppLifecycleState, MiniAppLifecycleChange } from './src/main/ets/core/lifecycle/MiniAppLifecycle';

/** 宿主接入入口：提供小程序信息即可，由容器自动管理适配与运行实例。 */
export { MiniAppContainer } from './src/main/ets/web/MiniAppContainer';

/** 应用级初始化入口，自动监听宿主生命周期。 */
export { MiniAppSDK } from './src/main/ets/core/MiniAppSDK';

/** 宿主控制当前小程序返回入口页或刷新。 */
export { MiniAppNavigationController } from './src/main/ets/web/MiniAppNavigationController';

/** 宿主提供的小程序启动信息。 */
export { MiniAppInfo, MiniAppOptions, MiniAppOpenHandler } from './src/main/ets/core/MiniAppOptions';

export { MiniAppAdapter } from './src/main/ets/core/MiniAppAdapter';

export { VendorAdapter, SwipeBackController } from './src/main/ets/core/VendorAdapter';

export { VkAdapter, VkHost, ClientMessageHandler } from './src/main/ets/vendors/vk/VkAdapter';

/** Debug 本地测试广告的宿主 UI 接入，非 VK 商业广告服务。 */
export { VkTestBannerController, VkTestBannerState } from './src/main/ets/vendors/vk/testing/VkTestBannerController';

export { VkTestNativeAdController,
  VkTestNativeAdState } from './src/main/ets/vendors/vk/testing/VkTestNativeAdController';

/** 宿主鉴权回调使用的请求、结果和函数类型。 */
export {
  AuthTokenRequest, AuthTokenResult, AuthTokenRequestHandler
} from './src/main/ets/vendors/vk/VkAdapter';

/** 宿主用户资料回调使用的请求、结果和函数类型。 */
export {
  UserInfoLocation,
  UserInfoRequest,
  UserInfoResult,
  UserInfoRequestHandler
} from './src/main/ets/vendors/vk/VkAdapter';

/** 容器向宿主报告的结构化错误。 */
export { MiniAppError } from './src/main/ets/core/MiniAppError';

/** 供宿主按 code 判断的稳定错误码。 */
export {
  HOST_LIFECYCLE_INIT_FAILED,
  VENDOR_NOT_SUPPORTED,
  VENDOR_NOT_READY,
  SESSION_CREATE_FAILED,
  VENDOR_BINDING_FAILED,
  VENDOR_LIFECYCLE_FAILED,
  SESSION_CLOSED,
  SESSION_ALREADY_ATTACHED_OR_CLOSED,
  CAPABILITY_ALREADY_REGISTERED_OR_INVALID,
  INVALID_ARGUMENT,
  PERMISSION_DENIED,
  USER_CANCELLED,
  CAPABILITY_BUSY,
  NOT_SUPPORTED,
  SYSTEM_ERROR,
  INVALID_CAPABILITY_RESULT,
  DOCUMENT_CHANGED,
  WEB_NOT_ATTACHED,
  WEB_SCRIPT_FAILED,
  WEB_CONTAINER_FAILED,
  WEB_RENDERER_EXITED,
  DUPLICATE_OR_INVALID_INJECTION
} from './src/main/ets/core/MiniAppErrorCode';

export { VK_VENDOR_ID } from './src/main/ets/vendors/vk/VkVendor';

/** LINE 宿主账号服务接入；容器入口仍为 MiniAppContainer。 */
export { LineAdapter } from './src/main/ets/vendors/line/LineAdapter';

export { LineMode } from './src/main/ets/vendors/line/LineMode';

/** 在创建 LINE 会话前，将公开 Custom Path 解析为真实 LIFF ID。 */
export { LineCustomPathResolver } from './src/main/ets/vendors/line/LineCustomPathResolver';

export { LineHost,
  LineRpcRequest,
  LineSubViewRequest,
  LineLiffViewResult } from './src/main/ets/vendors/line/liff/LineLiffTypes';

export { LineAccountManager } from './src/main/ets/vendors/line/auth/LineAccountManager';

export { LineHttpConnection, LineService } from './src/main/ets/vendors/line/network/LineTransport';

export { LineQrLoginState } from './src/main/ets/vendors/line/auth/LineAccountTypes';

export { LineEmailLoginState } from './src/main/ets/vendors/line/auth/LineEmailLoginTypes';

export { LineConnInfoProfile } from './src/main/ets/vendors/line/network/LineConnInfoConnection';

export { LineAccountOptions } from './src/main/ets/vendors/line/auth/LineAccountTypes';

// 宿主按稳定错误码选择恢复操作，无需复制 SDK 内部字符串。
export { LineErrorCode } from './src/main/ets/vendors/line/LineErrorCode';

export { LinePhoneRegistrationSession } from './src/main/ets/vendors/line/registration/LinePhoneRegistrationSession';
export { LinePhoneRegistrationState, LineRegistrationStage } from './src/main/ets/vendors/line/registration/LineRegistrationSessionTypes';
export { LinePhoneVerificationMethod, LineRegistrationPrivacy } from './src/main/ets/vendors/line/registration/LineRegistrationTypes';
export { LineRegistrationRequest } from './src/main/ets/vendors/line/registration/LineRegistrationUiTypes';
/** 宿主资源请求链契约；分发器保持内部实现。 */
export { WebRequest, WebRequestDecision, WebRequestChain, WebRequestHandler, WebRequestHandlerFactory } from './src/main/ets/web/request/WebRequestTypes';
