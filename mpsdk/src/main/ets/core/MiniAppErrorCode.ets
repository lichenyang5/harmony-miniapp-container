/** 厂商不受支持。 */
export const VENDOR_NOT_SUPPORTED: string = 'VENDOR_NOT_SUPPORTED';

/** 厂商未就绪。 */
export const VENDOR_NOT_READY: string = 'VENDOR_NOT_READY';

/** 创建会话失败。 */
export const SESSION_CREATE_FAILED: string = 'SESSION_CREATE_FAILED';

/** 厂商绑定失败。 */
export const VENDOR_BINDING_FAILED: string = 'VENDOR_BINDING_FAILED';

/** 厂商生命周期处理失败。 */
export const VENDOR_LIFECYCLE_FAILED: string = 'VENDOR_LIFECYCLE_FAILED';

/** 会话关闭。 */
export const SESSION_CLOSED: string = 'SESSION_CLOSED';

/** 会话已绑定或关闭。 */
export const SESSION_ALREADY_ATTACHED_OR_CLOSED: string = 'SESSION_ALREADY_ATTACHED_OR_CLOSED';

/** 能力名为空或重复。 */
export const CAPABILITY_ALREADY_REGISTERED_OR_INVALID: string = 'CAPABILITY_ALREADY_REGISTERED_OR_INVALID';

/** 参数无效。 */
export const INVALID_ARGUMENT: string = 'INVALID_ARGUMENT';

/** 必填参数未提供。 */
export const MISSING_REQUIRED_PARAMS: string = 'MISSING_REQUIRED_PARAMS';

/** 系统权限被拒绝。 */
export const PERMISSION_DENIED: string = 'PERMISSION_DENIED';

/** 用户主动取消原生交互。 */
export const USER_CANCELLED: string = 'USER_CANCELLED';

/** 同一宿主上下文的原生交互尚未结束。 */
export const CAPABILITY_BUSY: string = 'CAPABILITY_BUSY';

/** 当前宿主 UIAbility 尚未进入前台或已退后台。 */
export const APP_IN_BACKGROUND: string = 'APP_IN_BACKGROUND';

/** 宿主未接入生命周期通知，或已完成销毁。 */
export const HOST_LIFECYCLE_NOT_INITIALIZED: string = 'HOST_LIFECYCLE_NOT_INITIALIZED';

/** 当前平台或版本不支持该能力。 */
export const NOT_SUPPORTED: string = 'NOT_SUPPORTED';

/** 未分类的系统能力执行错误。 */
export const SYSTEM_ERROR: string = 'SYSTEM_ERROR';

/** 能力结果无效。 */
export const INVALID_CAPABILITY_RESULT: string = 'INVALID_CAPABILITY_RESULT';

/** 页面切换。 */
export const DOCUMENT_CHANGED: string = 'DOCUMENT_CHANGED';

/** 网页未绑定。 */
export const WEB_NOT_ATTACHED: string = 'WEB_NOT_ATTACHED';

/** 脚本执行失败。 */
export const WEB_SCRIPT_FAILED: string = 'WEB_SCRIPT_FAILED';

/** 网页容器失败。 */
export const WEB_CONTAINER_FAILED: string = 'WEB_CONTAINER_FAILED';

/** 渲染进程退出。 */
export const WEB_RENDERER_EXITED: string = 'WEB_RENDERER_EXITED';

/** 注入名为空或重复。 */
export const DUPLICATE_OR_INVALID_INJECTION: string = 'DUPLICATE_OR_INVALID_INJECTION';

/** 应用级宿主生命周期监听注册失败。 */
export const HOST_LIFECYCLE_INIT_FAILED: string = 'HOST_LIFECYCLE_INIT_FAILED';
