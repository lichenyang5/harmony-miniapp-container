import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { LINE_CLIENT_USER_AGENT } from '../../LineConstants';
import { LineConsentProtocol } from '../LineConsentProtocol';
import { SdkLogger } from '../../../../logging/SdkLogger';
import { LineErrorCode } from '../../LineErrorCode';
import { LineDialogInsets, readLineDialogInsets } from '../../LineDialogInsets';
import { LINE_CONSENT_BRIDGE_NAME, LineConsentBridge } from '../LineConsentBridge';
import { LineConsentSchemeHandler } from '../../scheme/LineConsentSchemeHandler';
import { WebSchemeDispatcher } from '../../../../web/scheme/WebSchemeDispatcher';
import { WebSchemeDecision, WebSchemeRequest } from '../../../../web/scheme/WebSchemeTypes';
import { MiniAppError } from '../../../../core/MiniAppError';

export interface LineConsentViewParams {
  hostWindow: window.Window;
  url: string;
  headers: webview.WebHeader[];
  complete: (allowed: boolean) => void;
  fail: () => void;
  openBrowser: (address: string) => Promise<void>;
}

@Builder
function buildLineConsent(params: LineConsentViewParams) {
  LineConsentView({ params })
}

export const lineConsentBuilder: WrappedBuilder<[LineConsentViewParams]> = wrapBuilder(buildLineConsent);

/** 官方授权页单独承载，不注入小程序代理、MST 或用户凭据脚本。 */
@ComponentV2
struct LineConsentView {
  @Require @Once @Param params: LineConsentViewParams;
  private controller: webview.WebviewController = new webview.WebviewController();
  private readonly bridge: LineConsentBridge = new LineConsentBridge(
    (): string => this.controller.getUrl(), (): void => {
    this.complete(true);
  });
  private loaded: boolean = false;
  private finishing: boolean = false;
  private proxyRegistered: boolean = false;
  private readonly schemeDispatcher: WebSchemeDispatcher<WebSchemeRequest> =
    new WebSchemeDispatcher<WebSchemeRequest>([new LineConsentSchemeHandler(
      (): string => this.controller.getUrl(), (allowed: boolean): void => {
      this.complete(allowed);
    })]);
  @Local private insets: LineDialogInsets = {
    top: 0,
    right: 0,
    bottom: 0,
    left: 0
  };
  private active: boolean = false;
  private listening: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.updateInsets();
    try {
      this.params.hostWindow.on('avoidAreaChange', this.avoidAreaChanged);
      this.listening = true;
    } catch (_) { /* 初始避让区仍然有效，部分窗口不支持变化监听。 */
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.stopCallbacks();
    if (this.proxyRegistered) {
      this.proxyRegistered = false;
      try {
        this.controller.deleteJavaScriptRegister(LINE_CONSENT_BRIDGE_NAME);
      } catch (_) { /* 已解绑的控制器无需再次清理。 */
      }
    }
    if (this.listening) {
      this.listening = false;
      try {
        this.params.hostWindow.off('avoidAreaChange', this.avoidAreaChanged);
      } catch (_) { /* 窗口可能已销毁。 */
      }
    }
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.mp_line_consent_title'))
          .layoutWeight(1)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111111')
          .maxLines(1)
        Button($r('app.string.mp_line_consent_cancel'), { type: ButtonType.Normal })
          .height(48)
          .fontSize(16)
          .fontColor('#111111')
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .padding({ left: 12, right: 0 })
          .onClick((): void => {
            this.complete(false);
          })
      }.width('100%').height(56).padding({ left: 16, right: 16 })
      .border({ width: { bottom: 0.5 }, color: '#E5E5E5' })

      Web({ src: '', controller: this.controller })
        .keyboardAvoidMode(WebKeyboardAvoidMode.RESIZE_CONTENT)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        // _blank 转为顶层导航，统一由下方拦截决定原页加载或打开普通浏览器。
        .multiWindowAccess(false)
        .onControllerAttached((): void => {
          this.load();
        })
        .onLoadIntercept((event): boolean => {
          if (!event) {
            return true;
          }
          const request: WebSchemeRequest = {
            url: event.data.getRequestUrl(), isMainFrame: event.data.isMainFrame()
          };
          return this.interceptWebScheme(request);
        })
        .onErrorReceive((event): void => {
          if (event?.request.isMainFrame()) {
            this.fail();
          }
        })
        .onHttpErrorReceive((event): void => {
          // 官方 400/无权限页面保留展示，不把“网页已加载”当作授权成功。
          if (event?.request.isMainFrame()) {
            SdkLogger.warn('LineConsent', 'httpFailed', { code: LineErrorCode.CONSENT_UI_FAILED });
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
        .onRenderExited((): void => {
          this.fail();
        })
        .width('100%')
        .layoutWeight(1)
    // Dialog 固定外框，网页输入仅由 Web 的 keyboardAvoidMode 调整视口。
    }.width('100%').height('100%')
    .padding(this.insets).backgroundColor(Color.White)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END])
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

  private load(): void {
    if (!this.active || this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const address: string = LineConsentProtocol.validateUrl(this.params.url);
      // 必须在首个文档加载前注册；官方成功页会轮询 window.line 并调用此方法。
      this.controller.registerJavaScriptProxy(this.bridge, LINE_CONSENT_BRIDGE_NAME, ['onUserAllowed'], []);
      this.proxyRegistered = true;
      this.controller.setCustomUserAgent(LINE_CLIENT_USER_AGENT.replace(' LIFF', ''));
      this.controller.loadUrl(address, this.params.headers);
    } catch (_) {
      this.fail();
    }
  }

  private complete(allowed: boolean): void {
    if (!this.active || this.finishing) {
      return;
    }
    this.finishing = true;
    this.stopCallbacks();
    this.params.complete(allowed);
  }

  private fail(): void {
    if (!this.active || this.finishing) {
      return;
    }
    this.finishing = true;
    this.stopCallbacks();
    this.params.fail();
  }

  /** 完成、失败和销毁共用的幂等回调停用入口。 */
  private stopCallbacks(): void {
    this.bridge.dispose();
    this.schemeDispatcher.dispose();
  }

  private interceptWebScheme(request: WebSchemeRequest): boolean {
    SdkLogger.info('LineConsent', 'navigationReceived', { code: request.isMainFrame ? 'MAIN_FRAME' : 'SUBFRAME' });
    SdkLogger.debug('LineConsent', 'navigationRequest', { data: request.url });
    if (!this.active || this.finishing) {
      return true;
    }
    if (this.schemeDispatcher.dispatch(request) !== WebSchemeDecision.PASS) {
      return true;
    }
    // PASS 仅表示没有协议处理器接管；携带账号身份的授权页仍必须限制加载来源。
    try {
      LineConsentProtocol.validateUrl(request.url);
      return false;
    } catch (_) {
      if (request.isMainFrame) {
        SdkLogger.info('LineConsent', 'browserOpening');
        this.params.openBrowser(request.url).catch((error: Object): void => {
          SdkLogger.warn('LineConsent', 'browserOpenFailed', {
            code: MiniAppError.from(error, LineErrorCode.BROWSER_FAILED, 'Unable to open consent link').code
          });
        });
      }
      return true;
    }
  }
}
