import { WebNewWindow, WebNewWindowRequest } from '../../web/WebNewWindowRequest';
import { LineSharePickerSchemeHandler } from './scheme/LineSharePickerSchemeHandler';
import { LineBrowserHost } from './browser/LineBrowserHost';
import { validateLineBrowserUrl } from './browser/LineBrowserUrl';
import { LINE_LIFF_HOST, LINE_MINIAPP_HOST } from './scheme/LineSchemeConstants';
import { LineQrCodeReaderSchemeHandler } from './scheme/LineQrCodeReaderSchemeHandler';
import { LineErrorCode } from './LineErrorCode';
import { MiniAppError } from '../../core/MiniAppError';
import { webview } from '@kit.ArkWeb';
import { DOCUMENT_CHANGED, INVALID_ARGUMENT, NOT_SUPPORTED, SESSION_CLOSED, VENDOR_BINDING_FAILED, VENDOR_LIFECYCLE_FAILED } from '../../core/MiniAppErrorCode';
import { SwipeBackController } from '../../core/VendorAdapter';
import { MiniAppInfo } from '../../core/MiniAppOptions';
import {
  BridgeInjection,
  DocumentScript,
  WebLoadHeader,
  WebLoadRequest,
  MiniAppDescriptor,
  MiniAppSession,
  SessionWebSchemeRequest,
  Vendor,
  VendorBinding
} from '../../core/Runtime';
import { WebSchemeHandler } from '../../web/scheme/WebSchemeTypes';
import { WebSystemSchemeHandler } from '../../web/scheme/WebSystemSchemeHandler';
import { LineLiffSchemeHandler, LineLiffSchemePorts } from './scheme/LineLiffSchemeHandler';
import { LineLiffLinkSchemeHandler, LineLiffLinkSchemePorts } from './scheme/LineLiffLinkSchemeHandler';
import { SdkLogger } from '../../logging/SdkLogger';
import { LineAdapter } from './LineAdapter';
import { LineBridgeProxy } from './LineBridgeProxy';
import { LineEventRegistry } from './LineEventRegistry';
import { LineEventHandler } from './LineEventHandler';
import { LineAppState, LineAppStateProvider } from './LineAppState';
import { LineModalSessionToken } from './LineModalSessionToken';
import { LineLiffDocument } from './liff/LineLiffDocument';
import { LineWindowController, LineWindowHost } from './LineWindowController';
import { LineLiffViewResult, LineSubViewLaunch } from './liff/LineLiffTypes';
import { LineDialogCallbacks, LineDialogHost } from './LineDialogHost';
import { LineMainViewService } from './liff/LineMainViewService';
import {
  LINE_CLIENT_USER_AGENT,
  LINE_LIFF_FULL_VIEW_TYPE,
  LINE_VENDOR_ID,
  LINE_WEB_USER_AGENT
} from './LineConstants';
import { LineCloseWindowHandler } from './handlers/LineCloseWindowHandler';
import { LineScanCodeHandler } from './handlers/LineScanCodeHandler';
import { ExtScanCodeV2Handler } from './handlers/ext/ExtScanCodeV2Handler';
import { LineOpenWindowHandler } from './handlers/LineOpenWindowHandler';
import { LineMode } from './LineMode';
import { LineAccountManager } from './auth/LineAccountManager';
import { LineLoginRequest } from './auth/LineLoginTypes';
import { createLineLiffHeaders, LINE_LIFF_TOKEN_HEADER } from './liff/LineLiffHeaders';
import { LineConsentController } from './liff/LineConsentController';
import { LineConsentDialogHost } from './consent/ui/LineConsentDialogHost';
import { createLineWebDirectLaunchScript } from './script/LineWebDirectLaunch';
import { LineWebLoginSchemeHandler } from './scheme/LineWebLoginSchemeHandler';
import { createLineLiffApiProxyScript } from './script/LineLiffApiProxyScript';
import { createLineLiffContextOverrideScript } from './script/LineLiffContextOverride';
import { createLineLiffLoginScript } from './script/LineLiffLogin';
import { ExtScanCodeHandler } from './handlers/ext/ExtScanCodeHandler';

const TAG: string = 'LineBridge';

/** 子窗口不取得父页面侧滑控制权，释放时也不能改变父页面配置。 */
class LineChildSwipeController implements SwipeBackController {
  setEnabled(_enabled: boolean): void {
  }

  dispose(): void {
  }
}

/** 为单个 WebView 会话声明注入对象和兼容脚本。 */
export class LineBinding implements VendorBinding, LineAppStateProvider {
  injections: BridgeInjection[] = [];
  private webScripts: DocumentScript[] = [];
  private proxy: LineBridgeProxy;
  private readonly registry: LineEventRegistry;
  private readonly browser: LineBrowserHost;
  private session: MiniAppSession
  private disposed: boolean = false;
  private appState?: LineAppState;
  private document?: LineLiffDocument;
  private windows?: LineWindowController;
  private dialog?: LineDialogHost;
  private launch?: LineSubViewLaunch;
  private mainResult?: LineLiffViewResult;
  private accountInvalidated?: () => void;
  private observedAccount?: LineAccountManager;
  private loginRequest?: LineLoginRequest;
  private consent?: LineConsentController;

  get scripts(): DocumentScript[] {
    if (this.disposed) {
      return [];
    }
    return this.document ? this.document.getScripts() : this.webScripts;
  }

  constructor(session: MiniAppSession, launch?: LineSubViewLaunch) {
    this.session = session
    this.launch = launch;
    this.registry = new LineEventRegistry(session);
    const adapter = session.getAdapter<LineAdapter>();
    this.proxy = new LineBridgeProxy(this.registry, session, this);
    this.browser = new LineBrowserHost(session.uiAbilityContext,
      (app: MiniAppInfo): Promise<void> => session.requestOpenMiniApp(app), adapter, session.lifecycle);
    if (adapter.mode === LineMode.WEB) {
      // WEB 入口固定使用已验证兼容 UA，不残留调用方此前的 LINE 兼容 UA 或追加参数。
      session.info.customUserAgent = session.info.customUserAgent ?? LINE_WEB_USER_AGENT;
      session.info.extraUserAgentParams = undefined;
      this.webScripts.push(createLineLiffContextOverrideScript(adapter.webContextType));
      if (adapter.forceLogin) {
        this.webScripts.push(createLineLiffLoginScript());
      }
      this.webScripts.push(createLineWebDirectLaunchScript());
      this.registerWebModeHandlers();
      this.webScripts.push(createLineLiffApiProxyScript(this.registry.getExtHandlerNames()));
      return;
    }
    session.info.customUserAgent = session.info.customUserAgent ?? LINE_CLIENT_USER_AGENT;
    if (adapter.mode === LineMode.WEB_HOOK) {
      this.registerWebModeHandlers();
      this.webScripts.push(createLineLiffContextOverrideScript(adapter.webContextType));
      if (adapter.forceLogin) {
        this.webScripts.push(createLineLiffLoginScript());
      }
      this.webScripts.push(createLineLiffApiProxyScript(this.registry.getExtHandlerNames(), true));
      return;
    }
    this.document = new LineLiffDocument(session, launch !== undefined);
    if (launch) {
      this.appState = { liffId: launch.liffId, featureToken: launch.result.featureToken! };
    } else if (!launch) {
      this.consent = new LineConsentController(new LineConsentDialogHost(session.uiAbilityContext));
      this.windows = new LineWindowController(session, adapter,
        (id: string, info: MiniAppInfo, childLaunch: LineSubViewLaunch): MiniAppSession => {
          const descriptor: MiniAppDescriptor = {
            info,
            vendor: new LineVendor(childLaunch),
            adapter,
            swipeBackController: new LineChildSwipeController(),
            onClose: childLaunch.onClose,
            onOpenMiniApp: (app: MiniAppInfo): Promise<void> => session.requestOpenMiniApp(app)
          };
          return new MiniAppSession(id, descriptor, session.uiAbilityContext);
        }, this.consent);
      const account = session.getAdapter<LineAdapter>().getAccount();
      if (account) {
        this.observeAccount(account);
      }
      const callbacks: LineDialogCallbacks = {
        requestClose: (): void => {
          this.windows?.requestClose();
        },
        onFailure: (error: MiniAppError): void => {
          this.windows?.fail(error);
        },
        onError: (error: MiniAppError): void => {
          session.getAdapter<LineAdapter>().reportSubWindowError(error);
        }
      };
      this.dialog = new LineDialogHost(session.uiAbilityContext, callbacks);
      this.windows.attach(this.dialog);
    }
    const handlers: LineEventHandler[] = [];
    handlers.push(new LineCloseWindowHandler(session));
    handlers.push(new LineScanCodeHandler(session));
    handlers.push(new LineOpenWindowHandler(session, this.browser));
    this.registerHandlers(handlers);
  }

  private registerHandlers(handlers: LineEventHandler[]): void {
    try {
      this.registry.initHandler(handlers);
      this.injections = [{
        name: this.proxy.name,
        object: this.proxy,
        methods: ['postMessage', 'validateFeatureToken'],
        asyncMethods: []
      }];
    } catch (error) {
      // 批量注册失败时尚未移交所有权，包含构造到一半时已经创建的实例。
      for (const handler of handlers) {
        try {
          handler.dispose();
        } catch (_) {
          SdkLogger.warn(TAG, 'handlerDisposeFailed', { sessionId: this.session.id, code: VENDOR_LIFECYCLE_FAILED });
        }
      }
      this.dispose();
      throw MiniAppError.from(error as Object, VENDOR_BINDING_FAILED, 'LINE handler registration failed');
    }
  }

  private registerWebModeHandlers(): void {
    const handlers: LineEventHandler[] = [
      new LineCloseWindowHandler(this.session),
      new LineOpenWindowHandler(this.session, this.browser),
      new ExtScanCodeV2Handler(this.session),
      new ExtScanCodeHandler(this.session)
    ];
    this.registerHandlers(handlers);
  }

  attachWindowHost(host: LineWindowHost): void {
    this.windows?.attach(host);
  }

  detachWindowHost(host: LineWindowHost): void {
    this.windows?.detach(host);
  }

  requestSubWindowClose(): boolean {
    return this.windows?.requestClose() ?? false;
  }

  reportSubWindowFailure(error: MiniAppError): void {
    this.windows?.fail(error);
  }

  getInitialHeaders(): webview.WebHeader[] {
    const accessToken: string | undefined = this.launch?.result.accessToken ?? this.mainResult?.accessToken;
    return createLineLiffHeaders(accessToken);
  }

  async prepareInitialLoad(): Promise<WebLoadRequest> {
    return this.prepareLoad(this.session.initialUrl);
  }

  async prepareNavigation(url: string): Promise<WebLoadRequest> {
    try {
      const parsed = validateLineBrowserUrl(url);
      // 校验原始路径，避免 URL 规范化消除点路径后误接受其他入口。
      const path: RegExpMatchArray | null = url.match(/^https:\/\/[^/?#\\]+\/([^/?#\\]+)(?:[?#][\s\S]*)?$/i);
      const targetId: string | undefined = path ? decodeURIComponent(path[1]) : undefined;
      if (parsed.protocol !== 'https:' || parsed.port ||
        (parsed.hostname !== LINE_LIFF_HOST && parsed.hostname !== LINE_MINIAPP_HOST) ||
        !targetId || (targetId !== this.session.appId &&
        targetId !== this.session.getAdapter<LineAdapter>().getLiffId(this.session))) {
        throw new MiniAppError(INVALID_ARGUMENT, 'Navigation requires the current LINE mini app entry URL');
      }
    } catch (error) {
      throw MiniAppError.from(error as Object, INVALID_ARGUMENT, 'Invalid LINE navigation URL');
    }
    return this.prepareLoad(url, this.session.getDocumentId());
  }

  private async prepareLoad(url: string, documentId?: number): Promise<WebLoadRequest> {
    const adapter = this.session.getAdapter<LineAdapter>();
    if (adapter.mode === LineMode.WEB_HOOK || adapter.mode === LineMode.WEB || this.launch) {
      const headers: webview.WebHeader[] = this.getInitialHeaders();
      return {
        url,
        headers: headers.map((item): WebLoadHeader => ({
          name: item.headerKey, value: item.headerValue
        }))
      };
    }
    // 本会话尚未授权，恢复期间不得因旧凭据失效而关闭自身；其他已加载会话继续监听。
    if (documentId === undefined) {
      this.unobserveAccount();
      const login = adapter.requestLogin(this.session.uiAbilityContext);
      this.loginRequest = login;
      try {
        await login.result;
      } finally {
        if (this.loginRequest === login) {
          this.loginRequest = undefined;
        }
      }
    }
    if (this.disposed) {
      throw new MiniAppError(LineErrorCode.SESSION_CLOSED, 'LINE session closed');
    }
    if (documentId !== undefined && documentId !== this.session.getDocumentId()) {
      throw new MiniAppError(DOCUMENT_CHANGED, 'LINE document changed');
    }
    const account = adapter.getAccount();
    if (!account) {
      throw new MiniAppError(LineErrorCode.ACCOUNT_PROVIDER_REQUIRED, 'LINE account is unavailable');
    }
    this.observeAccount(account);
    const mainView = new LineMainViewService(account);
    const challenge: string | undefined = this.document?.getMst()?.challenge;
    if (!challenge) {
      throw new MiniAppError(LineErrorCode.MST_REQUIRED, 'LINE 主视图缺少会话挑战');
    }
    const accountVersion: number | undefined = account?.getVersion();
    const issue = (): Promise<LineLiffViewResult> => mainView.issue(
      adapter.getLiffId(this.session) ?? this.session.appId, url, challenge);
    const result: LineLiffViewResult = await (this.consent ? this.consent.run(account, issue) : issue());
    if (this.disposed) {
      throw new MiniAppError(LineErrorCode.SESSION_CLOSED, 'LINE 会话已关闭');
    }
    if (documentId !== undefined && documentId !== this.session.getDocumentId()) {
      throw new MiniAppError(DOCUMENT_CHANGED, 'LINE document changed');
    }
    if (accountVersion !== account?.getVersion()) {
      throw new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE 账号已切换');
    }
    if (this.mainResult && result.liffId !== this.appState?.liffId) {
      throw new MiniAppError(LineErrorCode.MAINVIEW_INVALID, 'LINE 当前视图的应用身份已改变');
    }
    this.mainResult = result;
    this.appState = { liffId: result.liffId!, featureToken: result.featureToken! };
    return { url: result.url, headers: [{ name: LINE_LIFF_TOKEN_HEADER, value: result.accessToken! }] };
  }

  // 不限制网页来源；系统授权、前台状态和请求生命周期仍由 Web 层检查。
  canUseMedia(_origin: string): boolean {
    return !this.disposed;
  }

  canUseGeolocation(_origin: string): boolean {
    return !this.disposed;
  }

  /** 由 ArkWeb 保留空白窗口、后续导航与网页窗口通信。 */
  onNewWindow(request: WebNewWindowRequest): WebNewWindow {
    if (this.disposed) throw new MiniAppError(SESSION_CLOSED, 'LINE binding is closed');
    if (!request.isUserTrigger) throw new MiniAppError(NOT_SUPPORTED, 'User gesture is required');
    return this.browser.reserveWindow(request.url);
  }

  onDocumentChanged(documentId: number): void {
    this.browser.dismissAll();
    this.consent?.cancel();
    this.windows?.reset();
    this.proxy.onDocumentChanged();
    SdkLogger.debug(TAG, 'documentChanged', { sessionId: this.session.id, vendorId: LINE_VENDOR_ID, documentId });
  }

  getAppState(): LineAppState | undefined {
    if (this.disposed || !this.appState) {
      return undefined;
    }
    return {
      liffId: this.appState.liffId,
      featureToken: this.appState.featureToken,
      lineMode: this.session.getAdapter<LineAdapter>().mode
    };
  }

  /** 原生内部使用，不注册为网页代理方法。 */
  getModalSessionToken(): LineModalSessionToken | undefined {
    return this.document?.getMst();
  }

  createWebSchemeHandlers(): WebSchemeHandler<SessionWebSchemeRequest>[] {
    const systemHandler = new WebSystemSchemeHandler(this.session.uiAbilityContext);
    const mode = this.session.getAdapter<LineAdapter>().mode;

    const ports: LineLiffSchemePorts = {
      session: this.session,
      isChild: this.launch !== undefined,
      establishAppState: (state: LineAppState): void => {
        if (!this.appState) {
          this.appState = state;
          SdkLogger.info(TAG, 'appStateEstablished',
            { sessionId: this.session.id, documentId: this.session.getDocumentId() });
        }
      },
      openSubWindow: (address: string): void => {
        const mst = this.document?.getMst();
        if (mst) {
          this.windows?.open(address, mst.verifier);
        }
      }
    };
    const qrCodeReaderSchemeHandler = new LineQrCodeReaderSchemeHandler<SessionWebSchemeRequest>(this.session.uiAbilityContext, {
      isCurrent: (request: SessionWebSchemeRequest): boolean =>
      !this.disposed && !this.session.isClosed() && this.session.lifecycle.isForeground() &&
        request.documentId === this.session.getDocumentId(),
      openMiniApp: (app: MiniAppInfo): Promise<void> => this.session.requestOpenMiniApp(app)
    }, mode);
    const lineLiffSchemeHandler = new LineLiffSchemeHandler(ports, mode);
    if (mode === LineMode.WEB_HOOK) {
      return [systemHandler, lineLiffSchemeHandler, qrCodeReaderSchemeHandler, new LineSharePickerSchemeHandler(this.session)];
    }
    if (mode === LineMode.WEB) {
      return [systemHandler, lineLiffSchemeHandler, qrCodeReaderSchemeHandler];
    }
    const linkPorts: LineLiffLinkSchemePorts = {
      session: this.session,
      // APK 子视图走独立启动分支；主视图的缺省类型沿用 SDK 的 FULL 展示。
      canTransition: (): boolean => this.launch !== undefined || (this.mainResult !== undefined &&
        (this.mainResult.viewType === undefined || this.mainResult.viewType === LINE_LIFF_FULL_VIEW_TYPE))
    };
    const handlers: WebSchemeHandler<SessionWebSchemeRequest>[] =
      [lineLiffSchemeHandler, new LineLiffLinkSchemeHandler(linkPorts), qrCodeReaderSchemeHandler];
    handlers.push(new LineWebLoginSchemeHandler({
      source: 'liff', session: this.session, window: this.document!,
      consent: new LineConsentDialogHost(this.session.uiAbilityContext),
      onFailure: (error: MiniAppError): void => {
        SdkLogger.warn('LineWebLogin', 'failed', { sessionId: this.session.id, code: error.code });
      }
    }));
    handlers.push(systemHandler);
    return handlers;
  }

  onPageFinished(documentId: number): void {
    if (this.disposed || documentId !== this.session.getDocumentId()) {
      return;
    }
    const mode = this.session.getAdapter<LineAdapter>().mode;
    if (mode !== LineMode.CLIENT) {
      // 文档开始脚本负责避免引导页闪现；此处兜底处理 ArkWeb 未执行文档规则的情况。
      this.session.send(createLineWebDirectLaunchScript().script);
    }
    const features: string = JSON.stringify(this.registry.getFeatures());
    const scopes: string = JSON.stringify(this.launch?.result.scopes ?? this.mainResult?.scopes ?? []);
    this.proxy.onPageFinished(documentId);
    SdkLogger.debug(TAG, 'bridgeFeaturesPublishing', {
      sessionId: this.session.id,
      documentId,
      data: JSON.stringify({
        bridgeName: this.proxy.name,
        features: this.registry.getFeatures().join(',')
      })
    });
    // 主/子窗口仅交付各自发行响应中的 scopes；先设属性兼容 SDK 延迟加载。
    this.session.send(`(function () {
      if (!window._liff) {
        console.debug('[LINE Bridge] ready skipped reason=BRIDGE_MISSING');
        return;
      }
      window._liff.features = ${features};
      window._liff.scopes = ${scopes};
      console.debug('[LINE Bridge] ready published');
      if (window.liff && typeof window.liff._dispatchEvent === 'function') {
        window.liff._dispatchEvent(JSON.stringify({
          type: 'ready', callbackId: '',
          data: { features: window._liff.features, scopes: window._liff.scopes }
        }));
      }
    })();`);
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.proxy.dispose();
    this.registry.dispose();
    this.browser.dispose();
    this.loginRequest?.cancel();
    this.loginRequest = undefined;
    this.consent?.cancel();
    this.consent = undefined;
    this.unobserveAccount();
    this.appState = undefined;
    this.document?.dispose();
    this.windows?.dispose();
    this.windows = undefined;
    this.dialog?.dispose();
    this.dialog = undefined;
    this.launch = undefined;
    this.mainResult = undefined;
    this.injections = [];
    this.webScripts = [];
    SdkLogger.info(TAG, 'bindingDisposed', { sessionId: this.session.id, vendorId: LINE_VENDOR_ID });
  }

  private observeAccount(account: LineAccountManager): void {
    this.unobserveAccount();
    this.observedAccount = account;
    this.accountInvalidated = (): void => {
      if (this.disposed) {
        return;
      }
      try {
        this.session.requestClose();
      } catch (_) {
        this.session.close();
      }
    };
    account.addInvalidationListener(this.accountInvalidated);
  }

  private unobserveAccount(): void {
    if (this.observedAccount && this.accountInvalidated) {
      this.observedAccount.removeInvalidationListener(this.accountInvalidated);
    }
    this.observedAccount = undefined;
    this.accountInvalidated = undefined;
  }
}

/** 创建 LINE 调试容器的独立绑定，桥接能力后续扩展。 */
export class LineVendor implements Vendor {
  readonly vendorId: string = LINE_VENDOR_ID;
  private readonly launch?: LineSubViewLaunch;

  constructor(launch?: LineSubViewLaunch) {
    this.launch = launch;
  }

  createDefaultAdapter(): LineAdapter {
    return new LineAdapter(undefined);
  }

  createBinding(session: MiniAppSession): VendorBinding {
    const adapter = session.getAdapter()
    if (!(adapter instanceof LineAdapter)) {
      throw new MiniAppError(INVALID_ARGUMENT, 'line 厂商需要 LineAdapter');
    }
    const binding = new LineBinding(session, this.launch);
    SdkLogger.info(TAG, 'bindingCreated', { sessionId: session.id, vendorId: this.vendorId });
    return binding;
  }
}
