import { WebNewWindow, WebNewWindowRequest } from './WebNewWindowRequest';
import { WebRequestDecision } from './request/WebRequestTypes';
import { MiniAppLifecycleState } from '../core/lifecycle/MiniAppLifecycle';
import { DOCUMENT_CHANGED, NOT_SUPPORTED } from '../core/MiniAppErrorCode';
import { ArkWebEndpoint } from './ArkWebEndpoint';
import { webview } from '@kit.ArkWeb';
import { WebDocumentScriptInstaller } from './WebDocumentScriptInstaller';
import { MiniAppError } from '../core/MiniAppError';
import { SdkLogger } from '../logging/SdkLogger';
import { WebConsoleLogger } from '../logging/WebConsoleLogger';
import { BridgeInjection, DocumentScript, WebLoadRequest, MiniAppSession, SessionWebSchemeRequest } from '../core/Runtime';
import {
  DUPLICATE_OR_INVALID_INJECTION,
  SYSTEM_ERROR,
  VENDOR_LIFECYCLE_FAILED,
  WEB_CONTAINER_FAILED,
  WEB_RENDERER_EXITED
} from '../core/MiniAppErrorCode';
import BuildProfile from '../../../../BuildProfile';
import { MiniAppNavigationController, MiniAppNavigationEndpoint } from './MiniAppNavigationController';
import { documentEndScripts, mergeDocumentStartScripts, resolveUserAgent } from './MiniAppWebConfig';
import { ArkWebMediaRequest } from './ArkWebMediaRequest';
import { SessionWebMediaPermissions } from './SessionWebMediaPermissions';
import { ArkWebGeolocationRequest } from './ArkWebGeolocationRequest';
import { SessionWebGeolocationPermissions } from './SessionWebGeolocationPermissions';

/** 当前文件的 WebView 日志标识。 */
const TAG: string = 'WebView';

/** 当前模块使用的 PROXY_REMOVE_FAILED。 */
const PROXY_REMOVE_FAILED: string = 'PROXY_REMOVE_FAILED';

/** 当前模块使用的 WEB_HTTP_ERROR。 */
const WEB_HTTP_ERROR: string = 'WEB_HTTP_ERROR';

/** 当前模块使用的 WEB_LOAD_ERROR_PREFIX。 */
const WEB_LOAD_ERROR_PREFIX: string = 'WEB_LOAD_';

/** 延迟加载时不声明初始页面，由绑定完成后的 loadUrl 唯一发起入口加载。 */
const INITIAL_DOCUMENT_URL: string = '';
/** 用于辨识 WebView 自身的空白文档，不作为声明式初始地址。 */
const BLANK_DOCUMENT_URL: string = 'about:blank';
/** 页面诊断分类，不记录完整 URL 或查询参数。 */
const INITIAL_BLANK_DOCUMENT: string = 'INITIAL_BLANK_DOCUMENT';
const ENTRY_DOCUMENT: string = 'ENTRY_DOCUMENT';
const NAVIGATED_DOCUMENT: string = 'NAVIGATED_DOCUMENT';


/** 将宿主导航命令转发给当前 ArkWeb 控制器。 */
class ArkWebNavigationEndpoint implements MiniAppNavigationEndpoint {
  readonly controller: webview.WebviewController;
  readonly session: MiniAppSession;

  private readonly navigatePage: (address: string) => Promise<void>;

  constructor(controller: webview.WebviewController, session: MiniAppSession,
    navigatePage: (address: string) => Promise<void>) {
    this.navigatePage = navigatePage;
    this.controller = controller;
    this.session = session;
  }

  navigateTo(address: string): Promise<void> {
    return this.navigatePage(address);
  }

  goHome(): void {
    try {
      const entries = this.controller.getBackForwardEntries();
      const step: number = -entries.currentIndex;
      if (step < 0 && this.controller.accessStep(step)) {
        this.controller.backOrForward(step);
      }
    } catch (_) {
      SdkLogger.warn(TAG, 'homeNavigationFailed');
    }
  }

  refresh(): void {
    try {
      this.controller.refresh();
    } catch (_) {
      SdkLogger.warn(TAG, 'refreshFailed');
    }
  }
}

/** 在线小程序容器，负责代理注入和页面生命周期；组件消失后永久关闭所持有的会话。 */
@ComponentV2
export struct MiniAppView {
  @Local private documentStartScripts: DocumentScript[] = [];
  private scriptInstaller?: WebDocumentScriptInstaller;
  /** 必填的独立会话；同一实例不能挂载多个视图，挂载期间不应替换。 */
  @Require @Param session: MiniAppSession;
  private unobserveLifecycle?: () => void;

  private lifecycleChanged(state: MiniAppLifecycleState): void {
    if (state === MiniAppLifecycleState.DESTROYED || this.session.isClosed()) {
      this.release();
      return;
    }
    if (!this.attached || this.released) {
      return;
    }
    try {
      if (state === MiniAppLifecycleState.FOREGROUND) {
        this.controller.onActive();
      } else if (state === MiniAppLifecycleState.BACKGROUND) {
        this.controller.onInactive();
      }
    } catch (_) {
      SdkLogger.warn(TAG, 'webActivityChangeFailed', { sessionId: this.session.id, code: SYSTEM_ERROR });
    }
    if (state === MiniAppLifecycleState.FOREGROUND) {
      this.startInitialLoad();
    }
  }
  private attached: boolean = false;
  private initialLoadStarted: boolean = false;
  private pendingInitialLoad?: WebLoadRequest;
  private navigating: boolean = false;
  @Once @Param navigationController?: MiniAppNavigationController = undefined;
  /** 仅用于首次加载；不在后续任意网页导航中重复附加。 */
  @Once @Param initialHeaders?: webview.WebHeader[] = undefined;
  private controller: webview.WebviewController = new webview.WebviewController();
  private navigationEndpoint: MiniAppNavigationEndpoint | undefined = undefined;
  private registeredNames: string[] = [];
  private released: boolean = false;
  private preparingInitialLoad: boolean = false;
  private mediaPermissions?: SessionWebMediaPermissions;
  private geolocationPermissions?: SessionWebGeolocationPermissions;
  /** 导航句柄完成绑定后通知容器。 */
  @Event onNavigationReady: (controller: MiniAppNavigationController) => void =
    (_controller: MiniAppNavigationController): void => {
    };
  /** 初始化或渲染进程退出时的错误通知，不涵盖所有网页网络错误。 */
  @Event onError: (error: MiniAppError) => void = (_error: MiniAppError): void => {
  };

  /** 在 Web 创建前按 HAR 构建模式配置进程级网页调试开关。 */
  aboutToAppear(): void {
    this.documentStartScripts = mergeDocumentStartScripts(this.session.getBinding().scripts, this.session.info);
    try {
      webview.WebviewController.setWebDebuggingAccess(BuildProfile.DEBUG);
    } catch (error) {
      SdkLogger.warn(TAG, 'webDebuggingConfigurationFailed', { sessionId: this.session.id });
    }
  }

  /** 同步确认原生子窗口关系，再异步展示；绑定后不重新加载目标地址。 */
  private handleNewWindow(event: OnWindowNewEvent): void {
    const request: WebNewWindowRequest = {
      url: event.targetUrl, isUserTrigger: event.isUserTrigger, isAlert: event.isAlert,
      documentId: this.session.getDocumentId()
    };
    let popup: WebNewWindow | undefined;
    try {
      popup = this.session.openWebWindow(request);
    } catch (error) {
      this.reportNewWindowFailure(error as Object, request.documentId);
    }
    try {
      event.handler.setWebController(popup?.controller ?? null);
    } catch (_) {
      popup?.close();
      SdkLogger.warn(TAG, 'newWindowConfirmationFailed', { sessionId: this.session.id, code: SYSTEM_ERROR });
      return;
    }
    popup?.show().catch((error: Object): void => {
      popup?.close();
      this.reportNewWindowFailure(error, request.documentId);
    });
  }

  private reportNewWindowFailure(error: Object, documentId: number): void {
    const failure = MiniAppError.from(error, SYSTEM_ERROR, 'Unable to open new window');
    SdkLogger.warn(TAG, 'newWindowRejected', { sessionId: this.session.id, documentId, code: failure.code });
  }

  aboutToDisappear(): void {
    this.release();
  }

  /** 构建 WebView，安装文档脚本并转发页面、导航和渲染进程事件。 */
  build() {
    Web({
      src: INITIAL_DOCUMENT_URL,
      controller: this.controller,
      renderMode: this.session.info.isSyncLoad === true ? RenderMode.SYNC_RENDER : RenderMode.ASYNC_RENDER
    })
      .javaScriptAccess(true)
      .domStorageAccess(this.session.info.isOpenDomStorage ?? true)
      .fileAccess(false)
      .mixedMode(MixedMode.All)
      .geolocationAccess(this.session.info.isOpenGeolocation ?? true)
      .multiWindowAccess(this.session.isWebWindowEnabled())
      .allowWindowOpenMethod(this.session.isWebWindowEnabled())
      .onWindowNew((event) => {
        if (event) this.handleNewWindow(event);
      })
      .javaScriptOnDocumentStart(this.documentStartScripts)
      .javaScriptOnDocumentEnd(documentEndScripts(this.session.info))
      .onControllerAttached(() => this.attach())
      .onInterceptRequest((event) => {
        if (!event) return undefined;
        const decision = this.session.interceptWebRequest({
          url: event.request.getRequestUrl(), isMainFrame: event.request.isMainFrame(),
          resource: event.request, documentId: this.session.getDocumentId()
        });
        if (decision === WebRequestDecision.PASS) return undefined;
        if (decision.response) return decision.response;
        const response = new WebResourceResponse();
        response.setResponseCode(403);
        response.setReasonMessage('Forbidden');
        response.setResponseMimeType('text/plain');
        response.setResponseEncoding('utf-8');
        response.setResponseData('');
        return response;
      })
      .onLoadIntercept((event) => {
        if (!event) {
          return false;
        }
        const request: SessionWebSchemeRequest = {
          url: event.data.getRequestUrl(),
          isMainFrame: event.data.isMainFrame(),
          documentId: this.session.getDocumentId()
        };
        return this.session.interceptWebScheme(request);
      })
      .onSslErrorEvent((event: SslErrorEvent) => {
        if (this.session.info.isSSLIgnore === true) {
          event.handler.handleConfirm();
        } else {
          event.handler.handleCancel();
        }
      })
      .onSslErrorEventReceive((event) => {
        if (this.session.info.isSSLIgnore === true) {
          event.handler.handleConfirm();
        } else {
          event.handler.handleCancel();
        }
      })
      .onPermissionRequest((event) => {
        if (!event) {
          return;
        }
        const request = new ArkWebMediaRequest(event.request);
        if (this.session.lifecycle.isForeground() && this.mediaPermissions) {
          this.mediaPermissions.handle(request);
        } else {
          try {
            request.deny();
          } catch (_) { /* 已解绑的网页请求无需再次回调。 */
          }
        }
      })
      .onGeolocationShow((event) => {
        if (!event) {
          return;
        }
        const request = new ArkWebGeolocationRequest(event.origin, event.geolocation);
        if (this.session.lifecycle.isForeground() && this.geolocationPermissions) {
          this.geolocationPermissions.handle(request);
        } else {
          try {
            request.finish(false);
          } catch (_) { /* 网页请求可能已失效。 */
          }
        }
      })
      .onGeolocationHide(() => this.geolocationPermissions?.cancel())
      .onConsole((event) => {
        if (event) {
          WebConsoleLogger.write(event.message.getMessageLevel(), event.message.getMessage(),
            event.message.getSourceId(), event.message.getLineNumber(), this.session.id);
        }
        return false;
      })
      .onPageBegin((event) => {
        if (event) {
          SdkLogger.info(TAG, 'pageBeginning', {
            sessionId: this.session.id, code: this.classifyDocument(event.url)
          });
          try {
            this.session.beginDocument(event.url);
            this.mediaPermissions?.beginDocument(event.url);
            this.geolocationPermissions?.beginDocument(event.url);
          } catch (error) {
            this.release();
            this.onError(MiniAppError.from(error as Object, VENDOR_LIFECYCLE_FAILED, '更新厂商页面状态失败'));
          }
        }
      })
      .onPageEnd((event) => {
        // 页面结束事件不代表所有资源成功或厂商桥接已就绪。
        SdkLogger.info(TAG, 'pageEnded', {
          sessionId: this.session.id, documentId: this.session.getDocumentId(),
          code: this.classifyDocument(event?.url ?? INITIAL_DOCUMENT_URL)
        });
        if (event) {
          try {
            this.session.finishDocument(event.url);
          } catch (error) {
            this.onError(MiniAppError.from(error as Object, VENDOR_LIFECYCLE_FAILED, '通知厂商页面加载完成失败'));
          }
        }
      })
      .onErrorReceive((event) => {
        if (event && event.request.isMainFrame()) {
          SdkLogger.warn(TAG, 'mainFrameLoadFailed', {
            sessionId: this.session.id, documentId: this.session.getDocumentId(),
            code: WEB_LOAD_ERROR_PREFIX + event.error.getErrorCode()
          });
        }
      })
      .onHttpErrorReceive((event) => {
        if (event && event.request.isMainFrame()) {
          SdkLogger.warn(TAG, 'mainFrameHttpFailed', {
            sessionId: this.session.id, documentId: this.session.getDocumentId(), code: WEB_HTTP_ERROR
          });
        }
      })
      .onRenderExited(() => {
        this.handleRenderExited();
      })
      .width('100%')
      .height('100%')
  }

  /** 区分空白文档、入口和后续跳转，用于定位加载顺序。 */
  private classifyDocument(url: string): string {
    if (url === INITIAL_DOCUMENT_URL || url === BLANK_DOCUMENT_URL) {
      return INITIAL_BLANK_DOCUMENT;
    }
    if (url === this.session.initialUrl) {
      return ENTRY_DOCUMENT;
    }
    return NAVIGATED_DOCUMENT;
  }

  /** 控制器就绪后绑定运行时、注册厂商代理，再加载入口；失败时释放资源并通知宿主。 */
  private attach(): void {
    SdkLogger.debug(TAG, 'attaching', { sessionId: this.session.id });
    try {
      const userAgent: string = resolveUserAgent(this.controller.getUserAgent(), this.session.info);
      if (userAgent.trim().length > 0) {
        this.controller.setCustomUserAgent(userAgent);
      }
      const scriptInstaller = new WebDocumentScriptInstaller(this.getUIContext(), (scripts: DocumentScript[]): void => {
        this.documentStartScripts = mergeDocumentStartScripts(scripts, this.session.info);
      });
      this.scriptInstaller = scriptInstaller;
      this.session.attach(new ArkWebEndpoint(this.controller,
        (scripts: DocumentScript[]): Promise<void> => scriptInstaller.install(scripts)));
      this.mediaPermissions = new SessionWebMediaPermissions(this.session);
      this.geolocationPermissions = new SessionWebGeolocationPermissions(this.session);
      const injections = this.session.getBinding().injections;
      injections.forEach((injection: BridgeInjection) => {
        if (!injection.name || this.registeredNames.indexOf(injection.name) >= 0) {
          throw new MiniAppError(DUPLICATE_OR_INVALID_INJECTION, '注入对象名称为空或重复');
        }
        this.controller.registerJavaScriptProxy(injection.object, injection.name,
          injection.methods, injection.asyncMethods);
        this.registeredNames.push(injection.name);
      });
      SdkLogger.info(TAG, 'proxiesRegistered', {
        sessionId: this.session.id,
        count: this.registeredNames.length
      });
      SdkLogger.debug(TAG, 'proxyNamesRegistered', {
        sessionId: this.session.id,
        data: JSON.stringify({ names: this.registeredNames.join(',') })
      });
      this.navigationEndpoint = new ArkWebNavigationEndpoint(this.controller, this.session,
        (address: string): Promise<void> => this.navigateTo(address));
      if (this.navigationController) {
        this.navigationController.attach(this.navigationEndpoint);
        this.session.attachHostNavigation(this.navigationController);
      }
      this.attached = true;
      this.unobserveLifecycle = this.session.lifecycle.observe((change): void => this.lifecycleChanged(change.current));
      this.lifecycleChanged(this.session.lifecycle.getState());
    } catch (error) {
      this.release();
      this.onError(MiniAppError.from(error as Object, WEB_CONTAINER_FAILED, '初始化小程序 WebView 失败'));
      return;
    }
    // 宿主通知失败不影响已经绑定成功的会话和导航句柄。
    try {
      if (this.navigationController) {
        this.onNavigationReady(this.navigationController);
      }
    } catch (error) {
      SdkLogger.error(TAG, 'navigationReadyCallbackFailed',
        new MiniAppError(SYSTEM_ERROR, '宿主处理导航就绪通知失败', error as Object),
        { sessionId: this.session.id });
    }
  }

  private startInitialLoad(): void {
    if (!this.attached || !this.session.lifecycle.isForeground() || this.initialLoadStarted || this.released || this.navigating) {
      return;
    }
    this.initialLoadStarted = true;
    try {
      if (this.pendingInitialLoad) {
        const prepared = this.pendingInitialLoad;
        this.pendingInitialLoad = undefined;
        this.loadPreparedRequest(prepared);
      } else if (this.session.getBinding().prepareInitialLoad) {
        this.loadPrepared();
      } else {
        this.loadInitial(this.session.initialUrl, this.initialHeaders);
      }
    } catch (error) {
      this.failLoad(error as Object);
    }
  }

  private async navigateTo(address: string): Promise<void> {
    if (this.released || this.navigating || this.preparingInitialLoad) {
      throw new MiniAppError(NOT_SUPPORTED, 'Mini app loading is already in progress');
    }
    const binding = this.session.getBinding();
    if (!binding.prepareNavigation) {
      throw new MiniAppError(NOT_SUPPORTED, 'Vendor does not support mini app navigation');
    }
    this.navigating = true;
    let committing: boolean = false;
    try {
      const documentId: number = this.session.getDocumentId();
      const prepared: WebLoadRequest = await binding.prepareNavigation(address);
      this.session.getBinding();
      if (this.released || documentId !== this.session.getDocumentId()) {
        throw new MiniAppError(DOCUMENT_CHANGED, 'Document changed while preparing mini app');
      }
      const headers: webview.WebHeader[] = (prepared.headers ?? []).map((item): webview.WebHeader => ({
        headerKey: item.name, headerValue: item.value
      }));
      committing = true;
      this.controller.stop();
      this.session.beginDocument('');
      this.mediaPermissions?.cancel();
      this.geolocationPermissions?.cancel();
      this.session.getBinding();
      if (this.released || this.session.getDocumentId() !== documentId + 1) {
        throw new MiniAppError(DOCUMENT_CHANGED, 'Document changed while committing navigation');
      }
      this.loadInitial(prepared.url, headers);
      this.initialLoadStarted = true;
      this.pendingInitialLoad = undefined;
    } catch (error) {
      const failure = MiniAppError.from(error as Object, WEB_CONTAINER_FAILED, 'Mini app navigation failed');
      if (committing && failure.code !== DOCUMENT_CHANGED && !this.session.isClosed()) {
        this.failLoad(failure);
      }
      throw failure;
    } finally {
      this.navigating = false;
    }
  }

  private loadInitial(address: string, headers?: webview.WebHeader[]): void {
    if (this.released) {
      return;
    }
    if (headers && headers.length > 0) {
      this.controller.loadUrl(address, headers);
    } else {
      this.controller.loadUrl(address);
    }
    SdkLogger.info(TAG, 'loadRequested', { sessionId: this.session.id });
  }

  private async loadPrepared(): Promise<void> {
    this.preparingInitialLoad = true;
    try {
      const prepared: WebLoadRequest = await this.session.getBinding().prepareInitialLoad!();
      if (this.released) {
        return;
      }
      // 异步发行可能更新身份及注入内容，等待最新脚本提交后再加载或暂存入口。
      await this.scriptInstaller!.install(this.session.getBinding().scripts);
      if (this.released) {
        return;
      }
      if (!this.session.lifecycle.isForeground()) {
        this.pendingInitialLoad = prepared;
        this.initialLoadStarted = false;
        return;
      }
      this.session.getBinding();
      this.loadPreparedRequest(prepared);
    } catch (error) {
      this.failLoad(error as Object);
    } finally {
      this.preparingInitialLoad = false;
    }
  }

  private failLoad(error: Object): void {
    if (this.released) {
      return;
    }
    this.release();
    this.onError(MiniAppError.from(error, WEB_CONTAINER_FAILED, 'Preparing mini app entry failed'));
  }

  private loadPreparedRequest(prepared: WebLoadRequest): void {
    const headers: webview.WebHeader[] = (prepared.headers ?? []).map((item): webview.WebHeader => ({
      headerKey: item.name, headerValue: item.value
    }));
    this.loadInitial(prepared.url, headers);
  }

  private handleRenderExited(): void {
    if (this.released) {
      return;
    }
    // 异步准备期间仍是空白文档。临时 WebView 关闭可能使共享进程退出，后续 loadUrl 可重建渲染进程。
    if (this.preparingInitialLoad) {
      SdkLogger.info(TAG, 'initialRendererExited', { sessionId: this.session.id, code: WEB_RENDERER_EXITED });
      return;
    }
    this.release();
    this.onError(new MiniAppError(WEB_RENDERER_EXITED, '小程序渲染进程已退出'));
  }

  /** 关闭会话并尝试移除已注入的代理对象，允许控制器已解绑。 */
  private release(): void {
    if (this.released) {
      return;
    }
    this.released = true;
    this.scriptInstaller?.dispose();
    this.scriptInstaller = undefined;
    try {
      this.controller.stop();
    } catch (_) {
      SdkLogger.warn(TAG, 'loadStopFailed', { sessionId: this.session.id, code: SYSTEM_ERROR });
    }
    this.unobserveLifecycle?.();
    this.unobserveLifecycle = undefined;
    this.pendingInitialLoad = undefined;
    SdkLogger.debug(TAG, 'releasing', { sessionId: this.session.id, count: this.registeredNames.length });
    this.mediaPermissions?.dispose();
    this.mediaPermissions = undefined;
    this.geolocationPermissions?.dispose();
    this.geolocationPermissions = undefined;
    try {
      this.controller.closeCamera();
    } catch (_) {
    }
    try {
      this.controller.stopAllMedia();
    } catch (_) {
    }
    if (this.navigationEndpoint) {
      if (this.navigationController) {
        this.session.detachHostNavigation(this.navigationController);
        this.navigationController.detach(this.navigationEndpoint);
      }
      this.navigationEndpoint = undefined;
    }
    this.session.close();
    this.registeredNames.forEach((name: string) => {
      try {
        this.controller.deleteJavaScriptRegister(name);
      } catch (_) {
        SdkLogger.warn(TAG, 'proxyRemovalFailed', { sessionId: this.session.id, code: PROXY_REMOVE_FAILED });
      }
    });
    this.registeredNames = [];
    SdkLogger.debug(TAG, 'released', { sessionId: this.session.id });
  }
}
