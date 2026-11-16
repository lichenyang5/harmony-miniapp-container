import { MiniAppError } from '../../../core/MiniAppError';
import { LineAccountManager } from '../auth/LineAccountManager';
import { LineMode } from '../LineMode';
import { LineSubViewPresentation } from './LineSubViewPresentation';

/** 宿主可代理同名官方 RPC；不得使用父网页 Token 代替子应用响应。 */
export interface LineSubViewRequest {
  liffId: string;
  msit: string;
  requestedUrl: string;
  domain?: string;
  interWindowSession?: string;
}

/** 子窗口关闭收尾；liffId 只用于账号传输头，不写入请求 struct。 */
export interface LineSubWindowResultRequest {
  liffId: string;
  msit: string;
  mstVerifier: string;
}

/** 主/子 LIFF 视图共同使用的发行结果；子视图专有字段为可选项。 */
export interface LineLiffViewResult extends LineSubViewPresentation {
  /** 服务端确认的真实 LIFF ID，可能与请求中的 Mini App 别名不同。 */
  liffId?: string;
  viewType?: string;
  url: string;
  contextToken?: string;
  accessToken?: string;
  featureToken?: string;
  idToken?: string;
  clientId?: string;
  scopes?: string[];
  directLinkV1?: boolean;
  directLinkV2?: boolean;
}

/** 交给宿主账号模块的二进制 RPC 请求；SDK 不固定服务器或账号身份。 */
export interface LineRpcRequest {
  /** 官方 LIFF RPC 方法名；这里不是 HTTP 请求方法。 */
  method: string;
  path: string;
  liffId: string;
  body: Uint8Array;
}

export interface LineHost {
  mode?: LineMode;

  /** 无可恢复账号时直接失败，不呈现交互登录；默认允许交互。 */
  loginPolicy?: 'interactive' | 'reuseOnly';

  /** WEB/WEB_HOOK：注入给 LIFF 上下文的类型值，默认 none；CLIENT 忽略。 */
  webContextType?: string;

  /** WEB/WEB_HOOK：LIFF 初始化后未登录时自动调用 liff.login()，默认 false；CLIENT 忽略。 */
  forceLogin?: boolean;
  account?: LineAccountManager;
  onSubWindowError?: (error: MiniAppError) => void;
  issueSubLiffView?: (request: LineSubViewRequest) => Promise<LineLiffViewResult>;

  /** 账号模块负责 LEGY 地址、账号鉴权头和 HTTP，返回原始 Compact 响应。 */
  sendLiffRpc?: (request: LineRpcRequest) => Promise<Uint8Array>;
}

/** 子 Binding 的不可共享启动上下文，仅原生内部使用。 */
export interface LineSubViewLaunch {
  liffId: string;
  msit: string;
  verifier: string;
  result: LineLiffViewResult;
  onClose: () => void;
}
