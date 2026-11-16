import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { LineDialogInsets, readLineDialogInsets } from '../LineDialogInsets';
import { validateLineBrowserUrl } from './LineBrowserUrl';
import { LINE_WEB_USER_AGENT } from '../LineConstants';
import { MiniAppInfo, MiniAppOpenHandler } from '../../../core/MiniAppOptions';
import { WebSchemeDispatcher } from '../../../web/scheme/WebSchemeDispatcher';
import { WebSystemSchemeHandler } from '../../../web/scheme/WebSystemSchemeHandler';
import { WebSchemeDecision, WebSchemeHandler, WebSchemeRequest } from '../../../web/scheme/WebSchemeTypes';
import { LineBrowserAppSchemeHandler } from '../scheme/LineBrowserAppSchemeHandler';
import { LineWebLoginSchemeHandler } from '../scheme/LineWebLoginSchemeHandler';
import { LineWebLoginNavigation, LineWebLoginWindow } from '../weblogin/LineWebLoginTypes';
import { MiniAppLifecycle } from '../../../core/lifecycle/MiniAppLifecycle';
import { LineAdapter } from '../LineAdapter';
import { LineConsentPresenter } from '../consent/LineConsentTypes';
import { validateLineWebLoginReturn } from '../weblogin/LineWebLoginUrl';
import { MiniAppError } from '../../../core/MiniAppError';
import { DOCUMENT_CHANGED } from '../../../core/MiniAppErrorCode';
import { SdkLogger } from '../../../logging/SdkLogger';

export interface LineBrowserNativeAuth {
  adapter: LineAdapter;
  lifecycle: MiniAppLifecycle;
  consent: LineConsentPresenter;
}

export interface LineBrowserViewParams {
  hostWindow: window.Window;
  url: string;
  /** 原生新窗口由内核导航，不能再手动加载 url。 */
  popupController?: webview.WebviewController;
  close: () => void;
  openMiniApp: MiniAppOpenHandler;
  back?: () => boolean;
  /** 只有所属容器的原生登录模式提供；普通 Web 模式不创建原生授权流程。 */
  nativeAuth?: LineBrowserNativeAuth;
  isAvailable: () => boolean;
}

@Builder
function buildLineBrowser(params: LineBrowserViewParams) {
  LineBrowserView({ params })
}

export const lineBrowserBuilder: WrappedBuilder<[LineBrowserViewParams]> = wrapBuilder(buildLineBrowser);

/** 网页浏览器使用 LINE WEB 兼容 UA，不注册 LINE Bridge 或继承小程序脚本、账号请求头。 */
@ComponentV2
struct LineBrowserView {
  @Require @Once @Param params: LineBrowserViewParams;
  private controller: webview.WebviewController = new webview.WebviewController();
  private active: boolean = false;
  private attached: boolean = false;
  private listening: boolean = false;
  private documentId: number = 0;
  private schemeDispatcher: WebSchemeDispatcher<WebSchemeRequest> = new WebSchemeDispatcher<WebSchemeRequest>([]);
  @Local private title: string = '';
  @Local private domain: string = '';
  @Local private progress: number = 0;
  @Local private failed: boolean = false;
  @Local private unsupported: boolean = false;
  @Local private insets: LineDialogInsets = { top: 0, right: 0, bottom: 0, left: 0 };

  private createSchemeHandlers(): WebSchemeHandler<WebSchemeRequest>[] {
    const handlers: WebSchemeHandler<WebSchemeRequest>[] = [];
    if (!this.params.popupController) handlers.push(new LineBrowserAppSchemeHandler({
      isActive: (): boolean => this.active,
      openMiniApp: (app: MiniAppInfo): Promise<void> => this.params.openMiniApp(app),
      onFailure: (): void => {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.mp_line_browser_open_failed') });
      }
    }));
    if (this.params.nativeAuth) {
      handlers.push(this.createWebLoginHandler(this.params.nativeAuth));
    }
    handlers.push(new WebSystemSchemeHandler(this.getUIContext().getHostContext() as common.UIAbilityContext));
    return handlers;
  }

  private createWebLoginHandler(auth: LineBrowserNativeAuth): LineWebLoginSchemeHandler {
    const window: LineWebLoginWindow = {
      getDocumentId: this.getDocumentId.bind(this),
      isCurrent: this.isCurrent.bind(this),
      prepare: this.prepare.bind(this)
    };
    return new LineWebLoginSchemeHandler({
      source: 'browser', adapter: auth.adapter, lifecycle: auth.lifecycle, consent: auth.consent, window,
      onFailure: (error: MiniAppError): void => {
        SdkLogger.warn('LineWebLogin', 'failed', { code: error.code, documentId: this.documentId });
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.mp_line_web_login_failed') });
      }
    });
  }

  /** 原生网页登录通过窗口方法访问当前组件的文档状态。 */
  private getDocumentId(): number {
    return this.documentId;
  }

  private isCurrent(documentId: number): boolean {
    return this.active && this.attached && documentId === this.documentId && this.params.isAvailable();
  }

  /** 准备时保留原 URL；实际加载时再次检查文档和 entry。 */
  private prepare(address: string, _approved: boolean, documentId: number): LineWebLoginNavigation {
    const target: string = validateLineWebLoginReturn(address);
    return {
      url: target,
      load: async (): Promise<void> => {
        if (!this.isCurrent(documentId)) {
          throw new MiniAppError(DOCUMENT_CHANGED, 'LINE browser document changed');
        }
        this.controller.loadUrl(target);
      }
    };
  }

  private beginDocument(): void {
    this.documentId++;
    this.schemeDispatcher.reset();
  }

  aboutToAppear(): void {
    this.active = true;
    if (this.params.popupController) this.controller = this.params.popupController;
    this.schemeDispatcher.dispose();
    this.schemeDispatcher = new WebSchemeDispatcher<WebSchemeRequest>(this.createSchemeHandlers());
    if (!this.isBlankPopup(this.params.url)) this.domain = validateLineBrowserUrl(this.params.url).hostname;
    this.params.back = (): boolean => this.goBack();
    this.updateInsets();
    try {
      this.params.hostWindow.on('avoidAreaChange', this.avoidAreaChanged);
      this.listening = true;
    } catch (_) { /* 部分窗口不支持监听，仍使用初始避让区。 */
    }
  }

  private isBlankPopup(address: string): boolean {
    return this.params.popupController !== undefined && (address === '' || address === 'about:blank');
  }

  private attachController(): void {
    if (!this.active || this.attached || !this.params.isAvailable()) return;
    this.attached = true;
    try {
      this.controller.setCustomUserAgent(LINE_WEB_USER_AGENT);
      if (!this.params.popupController) this.controller.loadUrl(this.params.url);
    } catch (_) {
      this.fail();
    }
  }

  private interceptNavigation(request: WebSchemeRequest): boolean {
    if (!this.active || !this.params.isAvailable()) return true;
    if (this.isBlankPopup(request.url)) return false;
    if (this.schemeDispatcher.dispatch(request) !== WebSchemeDecision.PASS) return true;
    try {
      validateLineBrowserUrl(request.url);
      return false;
    } catch (_) {
      return true;
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.schemeDispatcher.dispose();
    this.params.back = undefined;
    if (this.attached) {
      try {
        this.controller.stop();
      } catch (_) { /* WebView 可能已解绑，组件销毁仍继续。 */
      }
    }
    if (this.listening) {
      this.listening = false;
      try {
        this.params.hostWindow.off('avoidAreaChange', this.avoidAreaChanged);
      } catch (_) { /* 宿主窗口可能已销毁。 */
      }
    }
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        this.toolbarButton($r('sys.symbol.chevron_left'), $r('app.string.mp_line_browser_back'),
          (): void => {
            if (!this.goBack()) {
              this.params.close();
            }
          })
        Column({ space: 2 }) {
          Text(this.title || this.domain || $r('app.string.mp_line_browser_window'))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#111111').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(this.domain).fontSize(11).fontColor('#777777').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.toolbarButton($r('sys.symbol.arrow_clockwise'), $r('app.string.mp_line_browser_refresh'),
          (): void => this.reload())
        this.toolbarButton($r('sys.symbol.xmark'), $r('app.string.mp_line_browser_close'),
          (): void => this.params.close())
      }.width('100%').height(56).padding({ left: 8, right: 8 })
      .border({ width: { bottom: 0.5 }, color: '#E5E5E5' })
      if (this.progress < 100 && !this.failed) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%').height(2).color('#06C755')
      }
      Stack() {
        Web({ src: '', controller: this.controller })
          .keyboardAvoidMode(WebKeyboardAvoidMode.RESIZE_CONTENT)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(false)
          .onInterceptRequest((event): WebResourceResponse | null => {
            return event ? this.interceptResource(event.request.getRequestUrl()) : null;
          })
          .mixedMode(MixedMode.None)
          .multiWindowAccess(false)
          .onWindowExit((): void => this.params.close())
          .onControllerAttached((): void => this.attachController())
          .onLoadIntercept((event): boolean => {
            if (!this.active || !event) {
              return true;
            }
            const request: WebSchemeRequest = {
              url: event.data.getRequestUrl(), isMainFrame: event.data.isMainFrame()
            };
            return this.interceptNavigation(request);
          })
          .onPageBegin((event): void => {
            if (this.active && event) {
              this.beginDocument();
              this.failed = false;
              this.unsupported = false;
              this.progress = 0;
              this.title = '';
              try {
                this.domain = this.isBlankPopup(event.url) ? '' : validateLineBrowserUrl(event.url).hostname;
              } catch (_) {
                this.fail();
              }
            }
          })
          .onTitleReceive((event): void => {
            if (this.active && event) {
              this.title = event.title;
            }
          })
          .onProgressChange((event): void => {
            if (this.active && event) {
              this.progress = event.newProgress;
            }
          })
          .onErrorReceive((event): void => {
            if (event?.request.isMainFrame()) {
              this.fail();
            }
          })
          .onSslErrorEvent((event: SslErrorEvent): void => {
            event.handler.handleCancel();
            this.fail();
          })
          .onSslErrorEventReceive((event): void => {
            event.handler.handleCancel();
            this.fail();
          })
          .onRenderExited((): void => this.fail())
          .onDownloadStart((): void => {
            this.fail(true);
          })
          .width('100%').height('100%')
          .visibility(this.failed ? Visibility.Hidden : Visibility.Visible)
        if (this.failed) {
          Column({ space: 16 }) {
            Text(this.unsupported ? $r('app.string.mp_line_browser_download_unavailable') :
              $r('app.string.mp_line_browser_load_failed'))
              .fontSize(16).fontColor('#666666').textAlign(TextAlign.Center)
            Button($r('app.string.mp_line_browser_retry')).onClick((): void => this.reload())
          }.padding(24).width('100%')
        }
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(this.insets).backgroundColor(Color.White)
  }

  @Builder
  private toolbarButton(icon: Resource, label: Resource, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(icon).fontSize(22).fontColor(['#111111'])
    }.width(44).height(44).padding(0).borderRadius(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText(label)
    .onClick(action)
  }

  private readonly avoidAreaChanged: (event: window.AvoidAreaOptions) => void =
    (_event: window.AvoidAreaOptions): void => {
      if (this.active) {
        this.updateInsets();
      }
    };

  private updateInsets(): void {
    this.insets = readLineDialogInsets(this.params.hostWindow,
      (value: number): number => this.getUIContext().px2vp(value));
  }

  private goBack(): boolean {
    if (!this.active || !this.attached) {
      return false;
    }
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return true;
      }
    } catch (_) {
      this.fail();
    }
    return false;
  }

  /** 导航拦截不覆盖图片、脚本等子资源；fileAccess(false) 也不等价于关闭所有本地资源。 */
  private interceptResource(address: string): WebResourceResponse | null {
    if (this.active && !/^(file|content|resource):/i.test(address)) {
      return null;
    }
    const response: WebResourceResponse = new WebResourceResponse();
    response.setResponseCode(403);
    response.setReasonMessage('Forbidden');
    response.setResponseMimeType('text/plain');
    response.setResponseEncoding('utf-8');
    response.setResponseData('');
    response.setResponseIsReady(true);
    return response;
  }

  private reload(): void {
    if (!this.active || !this.attached) {
      return;
    }
    this.failed = false;
    this.unsupported = false;
    this.progress = 0;
    try {
      try {
        validateLineBrowserUrl(this.controller.getUrl());
      } catch (_) {
        if (this.params.popupController) {
          this.controller.refresh();
          return;
        }
        // 首次加载尚未形成文档时，refresh 只会刷新空白页。
        this.controller.loadUrl(this.params.url);
        return;
      }
      this.controller.refresh();
    } catch (_) {
      this.fail();
    }
  }

  private fail(unsupported: boolean = false): void {
    if (this.active) {
      this.failed = true;
      this.unsupported = unsupported;
      this.progress = 100;
    }
  }
}
