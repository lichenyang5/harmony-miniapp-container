import { WebRequestHandlerFactory } from '../web/request/WebRequestTypes';
import { MiniAppLifecycleController } from './lifecycle/MiniAppLifecycleController';
import { common } from '@kit.AbilityKit';

/** 宿主提供的业务启动信息；容器挂载后补齐运行上下文。 */
export interface MiniAppInfo {
  /** 非空的小程序业务标识，不作为网页自行声明的授权凭据。 */
  appId: string;

  /** SDK 内置厂商标识，例如 vk。 */
  vendor: string;

  /** HTTP/HTTPS 在线入口，默认只允许主页面在同来源内导航。 */
  url: string;

  /** 自定义 User-Agent；空白字符串不生效。 */
  customUserAgent?: string;

  /** 追加到最终 User-Agent 的独立键值参数。 */
  extraUserAgentParams?: Record<string, string>;

  /** 是否使用 ArkWeb 同步渲染模式，默认异步。 */
  isSyncLoad?: boolean;

  /** 是否开启 DOM Storage，默认开启。 */
  isOpenDomStorage?: boolean;

  /** 是否开启网页定位，默认开启。 */
  isOpenGeolocation?: boolean;

  /** 是否允许网页请求新窗口；未指定时由厂商 Binding 的承接能力决定。 */
  isOpenNewWindow?: boolean;

  /** 文档开始阶段追加执行的宿主脚本。 */
  jsOnDocStart?: string;

  /** 文档开始脚本匹配规则，默认匹配全部。 */
  jsOnDocStartRules?: string[];

  /** 文档结束阶段追加执行的宿主脚本。 */
  jsOnDocEnd?: string;

  /** 文档结束脚本匹配规则，默认匹配全部。 */
  jsOnDocEndRules?: string[];

  /** 是否忽略 SSL 证书错误，默认拒绝。 */
  isSSLIgnore?: boolean;
}

/** 宿主接受目标小程序打开请求后完成；不要求等待目标网页加载或关闭。 */
export type MiniAppOpenHandler = (app: MiniAppInfo) => Promise<void>;

/** createSession 的完整参数，上下文只属于本次容器挂载。 */
export interface MiniAppOptions extends MiniAppInfo {
  /** 宿主资源请求处理器工厂，SDK 处理器优先。 */
  createWebRequestHandlers?: WebRequestHandlerFactory;
  uiAbilityContext: common.UIAbilityContext;
  uiContext: UIContext;
  lifecycleController?: MiniAppLifecycleController;

  /** @internal 当前容器收到主动关闭请求后的通知。 */
  onClose?: () => void;

  /** @internal 由 MiniAppContainer 转接的目标小程序打开回调。 */
  onOpenMiniApp?: MiniAppOpenHandler;
}
