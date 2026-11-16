import { WebNewWindow, WebNewWindowRequest } from '../web/WebNewWindowRequest';
import { WebRequestDispatcher } from '../web/request/WebRequestDispatcher';
import { WebRequestErrorCode } from '../web/request/WebRequestErrorCode';
import { WebRequest, WebRequestDecision, WebRequestHandler, WebRequestHandlerFactory } from '../web/request/WebRequestTypes';
import { HostLifecycleMonitor, HostLifecycleObserver } from './HostLifecycleMonitor';
import { MiniAppLifecycle, MiniAppLifecycleChange, MiniAppLifecycleState } from './lifecycle/MiniAppLifecycle';
import { bindMiniAppLifecycle, MiniAppLifecycleController, MiniAppSessionLifecycle } from './lifecycle/MiniAppLifecycleController';
import { common } from '@kit.AbilityKit';
import { MiniAppError } from './MiniAppError';
import {
  DOCUMENT_CHANGED,
  NOT_SUPPORTED,
  SESSION_ALREADY_ATTACHED_OR_CLOSED,
  SESSION_CLOSED,
  SYSTEM_ERROR,
  VENDOR_BINDING_FAILED,
  WEB_NOT_ATTACHED,
  WEB_SCRIPT_FAILED
} from './MiniAppErrorCode';
import { SdkLogger } from '../logging/SdkLogger';
import { SwipeBackController, VendorAdapter } from './VendorAdapter';
import { MiniAppInfo, MiniAppOpenHandler } from './MiniAppOptions';
import { snapshotMiniAppInfo } from './MiniAppInfoSnapshot';
import { WebSchemeDispatcher } from '../web/scheme/WebSchemeDispatcher';
import { WebSchemeDecision, WebSchemeHandler, WebSchemeRequest } from '../web/scheme/WebSchemeTypes';
import { WebSchemeErrorCode } from '../web/scheme/WebSchemeErrorCode';

export { SwipeBackController } from './VendorAdapter';

const SESSION_TAG: string = 'Session';
const BRIDGE_TAG: string = 'Bridge';

/** 本次会话的内部配置；侧滑控制器由会话独占并负责释放。 */
export interface MiniAppDescriptor {
  info: MiniAppInfo;
  vendor: Vendor;
  adapter: VendorAdapter;
  swipeBackController: SwipeBackController;
  lifecycleController?: MiniAppLifecycleController;
  onClose?: () => void;
  onOpenMiniApp?: MiniAppOpenHandler;
  createWebRequestHandlers?: WebRequestHandlerFactory;
}

/** 厂商代理的注入声明；object 自行实现所暴露方法的业务逻辑。 */
export interface BridgeInjection {
  name: string;
  object: Object;
  methods: string[];
  asyncMethods: string[];
}

/** 在文档开始阶段执行的厂商兼容脚本。 */
export interface DocumentScript {
  script: string;
  scriptRules: string[];

  /** 基础初始化脚本：宿主配置替换普通厂商脚本时仍保留。 */
  required?: boolean;
}

/** 页面加载时附加的单个请求头。 */
export interface WebLoadHeader {
  name: string;
  value: string;
}

/** 首次加载与后续跳转共用的实际加载地址及请求头。 */
export interface WebLoadRequest {
  url: string;
  headers?: WebLoadHeader[];
}

/** WebView 脚本和媒体端口；页面生命周期由会话管理。 */
export interface WebEndpoint {
  evaluate(script: string): Promise<string>;

  /** 安装下一文档脚本后加载；异步准备完成时再次检查调用方的有效性。 */
  load(request: WebLoadRequest, scripts: DocumentScript[], isCurrent?: () => boolean): Promise<void>;

  /** 暂停当前网页中的全部音视频播放。 */
  pauseAllMedia(): void;
}

/** 当前 WebView 为网页显式返回请求提供的同步导航入口。 */
export interface HostNavigationHandler {
  handleHostGoBack(): void;
}

/** 注入对象使用的会话环境；原生工具由对象直接调用。 */
export interface BridgeContext {
  readonly id: string;
  readonly appId: string;
  readonly vendorId: string;

  /** 宿主指定的入口地址；实际 Session 提供，独立能力测试上下文可省略。 */
  readonly initialUrl?: string;
  readonly lifecycle?: MiniAppLifecycle;
  readonly uiAbilityContext: common.UIAbilityContext;

  /** 向指定页面回传脚本；页面失效、关闭或执行失败时返回 false。 */
  send(script: string): Promise<boolean>;

  /** 在当前 WebView 加载；文档代次防止异步加载覆盖其他页面。 */
  load?(request: WebLoadRequest, documentId: number, scripts: DocumentScript[]): Promise<void>;

  /** 异步操作应在开始时保存页面代次，回传时使用保存的值。 */
  getDocumentId(): number;

  /** 注册下次页面切换或关闭时执行的清理；已关闭时立即执行。 */
  addCleanup(cleanup: () => void): void;

  /** 暂停当前小程序网页中的全部音视频播放。 */
  pauseAllMedia(): void;

  setSwipeBackEnabled(enabled: boolean): void;

  /** 请求移除当前容器；不执行网页返回。独立能力上下文可不提供。 */
  requestClose?(): void;
  /** 仅转交小程序目标，具体页面与导航由所属容器的宿主决定。 */
  requestOpenMiniApp?(app: MiniAppInfo): Promise<void>;
}

/** 小程序会话在通用协议请求上附加页面代次，不要求其他 WebView 实现 Session。 */
export interface SessionWebSchemeRequest extends WebSchemeRequest {
  readonly documentId: number;
}

/** 每个会话独占注入对象和原生资源，由厂商绑定负责释放。 */
export interface VendorBinding {
  injections: BridgeInjection[];
  scripts: DocumentScript[];

  /** 同步预留原生子窗口，由 Web 层绑定内核窗口关系。 */
  onNewWindow?(request: WebNewWindowRequest): WebNewWindow;

  /** 授权完成后再加载入口；未实现时直接加载 session.initialUrl。 */
  prepareInitialLoad?(): Promise<WebLoadRequest>;

  /** 校验 URL 属于当前小程序并准备加载；未实现时不支持小程序内跳转。 */
  prepareNavigation?(url: string): Promise<WebLoadRequest>;

  onLifecycleChanged?(change: MiniAppLifecycleChange): void;

  /** 网页媒体来源策略，省略即拒绝；系统权限与请求生命周期由 Web 层管理。 */
  canUseMedia?(origin: string): boolean;

  /** 网页定位来源策略，省略即拒绝。 */
  canUseGeolocation?(origin: string): boolean;

  onDocumentChanged(documentId: number): void;

  /** 当前非空白文档加载结束；不代表厂商 SDK 或授权初始化成功。 */
  onPageFinished?(documentId: number): void;

  /** 每个会话创建一次独立处理器；不在共享 Adapter 上保存当前导航实例。 */
  createWebSchemeHandlers?(): WebSchemeHandler<SessionWebSchemeRequest>[];

  /** SDK 处理器先于宿主处理器，每次挂载创建独立实例。 */
  createWebRequestHandlers?: WebRequestHandlerFactory;

  dispose(): void;
}

/** 无会话状态的厂商定义，每次创建独立绑定。 */
export interface Vendor {
  vendorId: string;

  createDefaultAdapter(): VendorAdapter;

  createBinding(session: MiniAppSession): VendorBinding;
}

/** 将单个宿主的系统事件转交所属会话，不保存其他会话的前台状态。 */
class SessionHostLifecycleObserver implements HostLifecycleObserver {
  private readonly session: MiniAppSession;

  constructor(session: MiniAppSession) {
    this.session = session;
  }

  onForegroundChanged(foreground: boolean): void {
    this.session.lifecycle.setHostForeground(foreground);
  }

  onDestroyed(): void {
    this.session.close();
  }
}

/** 单个 WebView 会话，负责页面隔离、脚本发送及绑定生命周期。 */
export class MiniAppSession implements BridgeContext {
  readonly id: string;
  readonly initialUrl: string;
  readonly info: MiniAppInfo;
  readonly appId: string;
  readonly vendorId: string;
  readonly uiAbilityContext: common.UIAbilityContext;
  readonly descriptor: MiniAppDescriptor;
  private binding?: VendorBinding;
  private requestDispatcher?: WebRequestDispatcher<WebRequest>;
  private schemeDispatcher?: WebSchemeDispatcher<SessionWebSchemeRequest>;
  private resettingWebSchemes: boolean = false;
  private endpoint?: WebEndpoint;
  private closed: boolean = false;
  readonly lifecycle: MiniAppSessionLifecycle;
  private unobserveHost?: () => void;
  private documentId: number = 0;
  private documentUrl: string = '';
  private finishedDocumentId: number = -1;
  private cleanups: Array<() => void> = [];
  private readonly swipeBackController: SwipeBackController;
  private hostBackPressHandling: boolean = false;
  private swipeBackEnabled: boolean = true;
  private hostNavigation?: HostNavigationHandler;
  private onClose?: () => void;
  private onOpenMiniApp?: MiniAppOpenHandler;

  constructor(id: string, descriptor: MiniAppDescriptor, uiAbilityContext: common.UIAbilityContext) {
    this.id = id;
    // 生命周期回调仅由私有字段持有，避免 descriptor 在会话关闭后重复保留宿主闭包。
    this.descriptor = {
      info: descriptor.info,
      vendor: descriptor.vendor,
      adapter: descriptor.adapter,
      swipeBackController: descriptor.swipeBackController
    };
    this.info = descriptor.info;
    this.initialUrl = descriptor.info.url;
    this.appId = descriptor.info.appId;
    this.vendorId = descriptor.vendor.vendorId;
    this.uiAbilityContext = uiAbilityContext;
    this.swipeBackController = descriptor.swipeBackController;
    this.onClose = descriptor.onClose;
    this.onOpenMiniApp = descriptor.onOpenMiniApp;
    try {
      this.lifecycle = bindMiniAppLifecycle(descriptor.lifecycleController ?? new MiniAppLifecycleController());
    } catch (error) {
      this.releaseSwipeBackController();
      throw MiniAppError.from(error as Object, SESSION_ALREADY_ATTACHED_OR_CLOSED,
        'Lifecycle controller is already bound or closed');
    }
    SdkLogger.info(SESSION_TAG, 'creating', { sessionId: this.id, vendorId: this.vendorId });
    this.lifecycle.observe((change: MiniAppLifecycleChange): void => this.onLifecycleChanged(change));
    try {
      this.binding = descriptor.vendor.createBinding(this);
      const handlers: WebSchemeHandler<SessionWebSchemeRequest>[] = this.binding.createWebSchemeHandlers ?
        this.binding.createWebSchemeHandlers() : [];
      const schemeDispatcher = new WebSchemeDispatcher<SessionWebSchemeRequest>(handlers);
      if (this.closed) {
        schemeDispatcher.dispose();
        throw new MiniAppError(SESSION_CLOSED, '会话已关闭');
      }
      this.schemeDispatcher = schemeDispatcher;
      const requestHandlers: WebRequestHandler<WebRequest>[] = this.binding.createWebRequestHandlers ?
        this.binding.createWebRequestHandlers() : [];
      let hostHandlers: WebRequestHandler<WebRequest>[];
      try {
        hostHandlers = descriptor.createWebRequestHandlers ? descriptor.createWebRequestHandlers() : [];
      } catch (error) {
        // 宿主工厂失败时仍释放已创建的 SDK 请求处理器。
        const abandoned = new WebRequestDispatcher<WebRequest>(requestHandlers);
        abandoned.dispose();
        throw new MiniAppError(WebRequestErrorCode.INVALID_REGISTRATION, 'Host request handler factory failed', error as Object);
      }
      const requestDispatcher = new WebRequestDispatcher<WebRequest>(requestHandlers, hostHandlers);
      if (this.closed) {
        requestDispatcher.dispose();
        throw new MiniAppError(SESSION_CLOSED, '会话已关闭');
      }
      this.requestDispatcher = requestDispatcher;
      const observer = new SessionHostLifecycleObserver(this);
      const unsubscribe = HostLifecycleMonitor.observe(this.uiAbilityContext, observer);
      if (this.closed) {
        unsubscribe();
      } else {
        this.unobserveHost = unsubscribe;
      }
      SdkLogger.info(SESSION_TAG, 'created', { sessionId: this.id, vendorId: this.vendorId });
    } catch (error) {
      const failure = MiniAppError.from(error as Object, VENDOR_BINDING_FAILED, '创建厂商绑定失败');
      SdkLogger.debug(SESSION_TAG, 'bindingRejected',
        { sessionId: this.id, vendorId: this.vendorId, code: failure.code });
      this.close();
      throw failure;
    }
  }

  getAdapter<T extends VendorAdapter>(): T {
    return this.descriptor.adapter as T
  }

  /** 泛型用于厂商内部已知的 Binding 类型；省略时保留公共契约。 */
  getBinding<T extends VendorBinding = VendorBinding>(): T {
    if (!this.binding || this.closed) {
      throw new MiniAppError(SESSION_CLOSED, '会话已关闭或厂商绑定不可用');
    }
    return this.binding as T;
  }

  private onLifecycleChanged(change: MiniAppLifecycleChange): void {
    SdkLogger.info(SESSION_TAG, 'lifecycleChanged', {
      sessionId: this.id, vendorId: this.vendorId, code: change.previous + '->' + change.current
    });
    if (change.current === MiniAppLifecycleState.BACKGROUND && this.endpoint) {
      try {
        this.pauseAllMedia();
      } catch (_) {
        SdkLogger.warn(SESSION_TAG, 'mediaPauseFailed', { sessionId: this.id, code: SYSTEM_ERROR });
      }
    }
    this.binding?.onLifecycleChanged?.(change);
  }

  isClosed(): boolean {
    return this.closed;
  }

  /** 显式配置优先，未指定时由厂商是否实现窗口处理决定。 */
  isWebWindowEnabled(): boolean {
    return this.info.isOpenNewWindow ?? (this.binding?.onNewWindow !== undefined);
  }

  openWebWindow(request: WebNewWindowRequest): WebNewWindow {
    if (this.closed) throw new MiniAppError(SESSION_CLOSED, 'Source session is closed');
    if (!this.endpoint) throw new MiniAppError(WEB_NOT_ATTACHED, 'WebView is unavailable');
    if (request.documentId !== this.documentId) {
      throw new MiniAppError(DOCUMENT_CHANGED, 'New window request is no longer current');
    }
    if (!this.lifecycle.isForeground() || !this.isWebWindowEnabled() || !this.binding?.onNewWindow) {
      throw new MiniAppError(NOT_SUPPORTED, 'New window opening is unavailable');
    }
    return this.binding.onNewWindow(request);
  }

  getDocumentId(): number {
    return this.documentId;
  }

  /** 当前非空白文档已完成加载；不表示厂商 SDK 或授权初始化已完成。 */
  isDocumentFinished(documentId: number): boolean {
    return !this.closed && documentId > 0 && documentId === this.documentId &&
      documentId === this.finishedDocumentId;
  }

  /** 会话负责页面有效性，独立分发器负责资源请求处理。 */
  interceptWebRequest(request: WebRequest): WebRequestDecision {
    if (this.closed || !this.endpoint || request.documentId !== this.documentId) return WebRequestDecision.BLOCK;
    return this.requestDispatcher?.dispatch(request) ?? WebRequestDecision.BLOCK;
  }

  /** 会话负责有效性，独立分发器负责协议选择；仅 PASS 交回 WebView。 */
  interceptWebScheme(request: SessionWebSchemeRequest): boolean {
    if (this.closed || !this.endpoint || request.documentId !== this.documentId) {
      return true;
    }
    try {
      return (this.schemeDispatcher?.dispatch(request) ?? WebSchemeDecision.BLOCK) !== WebSchemeDecision.PASS;
    } catch (_) {
      SdkLogger.warn(SESSION_TAG, 'webSchemeHandlerFailed',
        { sessionId: this.id, documentId: this.documentId, code: WebSchemeErrorCode.HANDLER_FAILED });
      return true;
    }
  }

  /** 一个会话只能成功绑定一个 WebView。 */
  attach(endpoint: WebEndpoint): void {
    if (this.closed || this.endpoint) {
      throw new MiniAppError(SESSION_ALREADY_ATTACHED_OR_CLOSED, '会话已绑定视图或已经关闭');
    }
    this.endpoint = endpoint;
    this.lifecycle.setAttached();
    SdkLogger.info(SESSION_TAG, 'attached', { sessionId: this.id, documentId: this.documentId });
  }

  async load(request: WebLoadRequest, documentId: number, scripts: DocumentScript[]): Promise<void> {
    if (this.closed || !this.endpoint) {
      throw new MiniAppError(this.closed ? SESSION_CLOSED : WEB_NOT_ATTACHED, 'WebView is unavailable');
    }
    if (documentId !== this.documentId || !this.lifecycle.isForeground()) {
      throw new MiniAppError(DOCUMENT_CHANGED, 'WebView continuation is no longer current');
    }
    await this.endpoint.load(request, scripts, (): boolean => !this.closed &&
      documentId === this.documentId && this.lifecycle.isForeground());
  }

  /** 使旧页面回调失效，清理资源后通知厂商绑定。 */
  beginDocument(url: string): void {
    if (this.closed) {
      return;
    }
    this.documentId++;
    const documentId: number = this.documentId;
    this.documentUrl = url;
    SdkLogger.info(SESSION_TAG, 'documentChanged', { sessionId: this.id, documentId: this.documentId });
    this.swipeBackEnabled = true;
    this.runCleanups();
    if (this.closed || documentId !== this.documentId || this.resettingWebSchemes) {
      return;
    }
    this.resettingWebSchemes = true;
    try {
      this.requestDispatcher?.reset();
      this.schemeDispatcher?.reset();
    } finally {
      this.resettingWebSchemes = false;
    }
    // reset 钩子可能重入切文档；全部处理器清理完成后，只通知最新文档。
    if (!this.closed) {
      this.binding?.onDocumentChanged(this.documentId);
    }
  }

  /** 过滤空白页、已离开的 URL、重复完成及关闭后的通知。 */
  finishDocument(url: string): void {
    if (this.closed || !this.endpoint || this.documentId === 0 ||
      !url || url === 'about:blank' || url !== this.documentUrl ||
      this.finishedDocumentId === this.documentId) {
      return;
    }
    this.finishedDocumentId = this.documentId;
    this.binding?.onPageFinished?.(this.documentId);
  }

  addCleanup(cleanup: () => void): void {
    if (this.closed) {
      cleanup();
    } else {
      this.cleanups.push(cleanup);
    }
  }

  pauseAllMedia(): void {
    if (this.closed || !this.endpoint) {
      const code: string = this.closed ? SESSION_CLOSED : WEB_NOT_ATTACHED;
      throw new MiniAppError(code, '小程序网页未绑定或会话已关闭');
    }
    this.endpoint.pauseAllMedia();
  }

  setSwipeBackEnabled(enabled: boolean): void {
    if (this.closed) {
      throw new MiniAppError(SESSION_CLOSED, '会话已关闭');
    }
    if (this.hostBackPressHandling) {
      this.swipeBackEnabled = enabled;
      return;
    }
    try {
      this.swipeBackController.setEnabled(enabled);
    } catch (error) {
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, '设置原生侧滑返回失败');
    }
  }

  /** 宿主声明已将页面返回事件交给当前会话；不依赖 Circle 设备能力。 */
  enableBackPressHandling(): void {
    if (!this.closed) {
      this.hostBackPressHandling = true;
    }
  }

  /** 绑定当前视图的导航处理器；后绑定的视图不会被旧视图解绑。 */
  attachHostNavigation(navigation: HostNavigationHandler): void {
    if (!this.closed) {
      this.hostNavigation = navigation;
    }
  }

  detachHostNavigation(navigation: HostNavigationHandler): void {
    if (this.hostNavigation === navigation) {
      this.hostNavigation = undefined;
    }
  }

  /** 转交网页显式返回请求；未绑定或已关闭时安全消费。 */
  handleHostGoBack(): void {
    if (!this.closed) {
      this.hostNavigation?.handleHostGoBack();
    }
  }

  /** true 表示消费返回事件；未接入、默认开启或已关闭时交回宿主。 */
  handleBackPress(): boolean {
    return this.isBackPressHandlingEnabled() && !this.swipeBackEnabled;
  }

  /** 导航层仅可为已接入且未关闭的会话执行网页历史回退。 */
  isBackPressHandlingEnabled(): boolean {
    return !this.closed && this.hostBackPressHandling;
  }

  /** 提交前检查会话和端点，完成后检查会话是否关闭；页面代次由调用者校验，已提交脚本无法撤回。 */
  async send(script: string): Promise<boolean> {
    if (this.closed || !this.endpoint) {
      const code = this.closed ? SESSION_CLOSED : WEB_NOT_ATTACHED;
      SdkLogger.debug(BRIDGE_TAG, 'deliverySkipped', { sessionId: this.id, code });
      return false;
    }
    try {
      await this.endpoint.evaluate(script);
      const delivered = !this.closed;
      SdkLogger.debug(BRIDGE_TAG, 'deliveryCompleted',
        { sessionId: this.id, code: delivered ? 'OK' : DOCUMENT_CHANGED });
      return delivered;
    } catch (error) {
      SdkLogger.error(BRIDGE_TAG, 'deliveryFailed',
        MiniAppError.from(error as Object, WEB_SCRIPT_FAILED, '执行回传脚本失败'), { sessionId: this.id });
      return false;
    }
  }

  /** 回调只接受目标配置快照，不创建窗口；已提交给宿主的操作不会被 SDK 撤回。 */
  async requestOpenMiniApp(app: MiniAppInfo): Promise<void> {
    if (this.closed) {
      throw new MiniAppError(SESSION_CLOSED, 'Source session is closed');
    }
    if (!this.lifecycle.isForeground()) {
      throw new MiniAppError(NOT_SUPPORTED, 'Source session is inactive');
    }
    const open = this.onOpenMiniApp;
    if (!open) {
      throw new MiniAppError(NOT_SUPPORTED, 'Host mini app opening is unavailable');
    }
    const documentId: number = this.documentId;
    try {
      await open(snapshotMiniAppInfo(app));
    } catch (error) {
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, 'Host mini app opening failed');
    }
    if (this.closed || documentId !== this.documentId) {
      throw new MiniAppError(DOCUMENT_CHANGED, 'Source document changed while opening mini app');
    }
  }

  /** 网页主动关闭：先使会话失效，再通知所属容器移除视图与宿主退出。 */
  requestClose(): void {
    if (this.closed) {
      return;
    }
    const onClose = this.onClose;
    if (!onClose) {
      throw new MiniAppError(SYSTEM_ERROR, '容器未绑定关闭通知');
    }
    SdkLogger.info(SESSION_TAG, 'closeRequested', { sessionId: this.id, documentId: this.documentId });
    this.close();
    try {
      onClose();
    } catch (error) {
      // 退出回调异常也不能恢复已关闭的网页，或让请求重新交给网页宿主。
      SdkLogger.error(SESSION_TAG, 'closeNotificationFailed',
        MiniAppError.from(error as Object, SYSTEM_ERROR, '宿主关闭通知失败'), { sessionId: this.id });
    }
  }

  /** 永久关闭会话；厂商对象负责取消调用及释放其持有的原生工具。 */
  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      this.endpoint?.pauseAllMedia();
    } catch (_) {
      SdkLogger.warn(SESSION_TAG, 'mediaPauseFailed', { sessionId: this.id, code: SYSTEM_ERROR });
    }
    this.unobserveHost?.();
    this.unobserveHost = undefined;
    this.lifecycle.destroy();
    this.onClose = undefined;
    this.onOpenMiniApp = undefined;
    this.hostNavigation = undefined;
    this.documentId++;
    this.endpoint = undefined;
    this.releaseSwipeBackController();
    this.runCleanups();
    this.requestDispatcher?.dispose();
    this.requestDispatcher = undefined;
    this.schemeDispatcher?.dispose();
    this.schemeDispatcher = undefined;
    try {
      this.binding?.dispose();
    } catch (_) {
      SdkLogger.warn(SESSION_TAG, 'bindingDisposeFailed',
        { sessionId: this.id, code: 'BINDING_DISPOSE_FAILED' });
    }
    this.binding = undefined;
    SdkLogger.info(SESSION_TAG, 'closed', { sessionId: this.id });
  }

  /** 单个清理异常不会阻止其他资源释放。 */
  private runCleanups(): void {
    const cleanups = this.cleanups;
    this.cleanups = [];
    cleanups.forEach((cleanup: () => void) => {
      try {
        cleanup();
      } catch (_) {
        SdkLogger.warn(SESSION_TAG, 'cleanupFailed',
          { sessionId: this.id, code: 'RESOURCE_CLEANUP_FAILED' });
      }
    });
  }

  /** 释放会话的侧滑控制权；恢复失败不阻断其他资源释放。 */
  private releaseSwipeBackController(): void {
    try {
      this.swipeBackController.dispose();
    } catch (_) {
      SdkLogger.warn(SESSION_TAG, 'swipeBackRestoreFailed', {
        sessionId: this.id, code: 'SWIPE_BACK_RESTORE_FAILED'
      });
    }
  }
}
