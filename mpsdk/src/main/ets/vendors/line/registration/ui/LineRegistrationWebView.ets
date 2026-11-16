import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { LineDialogInsets, readLineDialogInsets } from '../../LineDialogInsets';
import { LINE_CLIENT_USER_AGENT } from '../../LineConstants';
import { LineRegistrationWebProtocol, RegistrationWebDecision, RegistrationWebKind, RegistrationWebResult } from './LineRegistrationWebProtocol';

export interface LineRegistrationWebViewParams {
  hostWindow: window.Window;
  address: string;
  headers: webview.WebHeader[];
  kind: RegistrationWebKind;
  protocol: LineRegistrationWebProtocol;
  active: () => boolean;
  complete: (result: RegistrationWebResult) => void;
  fatal: () => void;
}
@Builder
function buildLineRegistrationWeb(params: LineRegistrationWebViewParams) { LineRegistrationWebView({ params }) }
export const lineRegistrationWebBuilder: WrappedBuilder<[LineRegistrationWebViewParams]> = wrapBuilder(buildLineRegistrationWeb);

@ComponentV2
struct LineRegistrationWebView {
  @Require @Once @Param params: LineRegistrationWebViewParams;
  @Local private insets: LineDialogInsets = { top: 0, right: 0, bottom: 0, left: 0 };
  @Local private failed: boolean = false;
  @Local private loaded: boolean = false;
  private active: boolean = false;
  private attached: boolean = false;
  private listening: boolean = false;
  private readonly controller: webview.WebviewController = new webview.WebviewController();
  aboutToAppear(): void {
    this.active = true; this.updateInsets();
    try { this.params.hostWindow.on('avoidAreaChange', this.changed); this.listening = true; } catch (_) {}
  }
  aboutToDisappear(): void {
    this.active = false; this.params.protocol.stop();
    this.params.headers.length = 0;
    if (this.listening) { try { this.params.hostWindow.off('avoidAreaChange', this.changed); } catch (_) {} }
  }
  private readonly changed = (_event: window.AvoidAreaOptions): void => { if (this.active) { this.updateInsets(); } };
  private updateInsets(): void { this.insets = readLineDialogInsets(this.params.hostWindow, (n: number): number => this.getUIContext().px2vp(n)); }
  private complete(result: RegistrationWebResult): void {
    if (!this.active || !this.params.active()) { return; }
    this.params.protocol.stop(); this.params.complete(result);
  }
  build() {
    Column() {
      Row() {
        Text($r('app.string.mp_line_registration_review')).fontSize(20).layoutWeight(1)
        Button($r('app.string.mp_line_registration_close')).onClick((): void => this.complete(RegistrationWebResult.CLOSED))
      }.width('100%').padding(12)
      Web({ src: '', controller: this.controller })
        .javaScriptAccess(true).domStorageAccess(true).fileAccess(false).mixedMode(MixedMode.None)
        .multiWindowAccess(false).keyboardAvoidMode(WebKeyboardAvoidMode.RESIZE_CONTENT)
        .onControllerAttached((): void => {
          if (!this.active || !this.params.active() || this.attached) { return; }
          this.attached = true;
          try { this.controller.setCustomUserAgent(LINE_CLIENT_USER_AGENT.replace(' LIFF', '')); this.controller.loadUrl(this.params.address, this.params.headers); }
          catch (_) { this.failed = true; }
        })
        .onLoadIntercept((event): boolean => {
          if (!this.active || !this.params.active() || !event) { return true; }
          let current: string = '';
          try { current = this.controller.getUrl(); } catch (_) {}
          const decision = this.params.protocol.navigate(event.data.getRequestUrl(), event.data.isMainFrame(), current);
          if (decision === RegistrationWebDecision.ACCEPTED) { this.complete(RegistrationWebResult.ACCEPTED); }
          if (decision === RegistrationWebDecision.DECLINED) { this.complete(RegistrationWebResult.DECLINED); }
          if (decision === RegistrationWebDecision.FATAL) { this.params.protocol.stop(); this.params.fatal(); }
          return decision !== RegistrationWebDecision.LOAD;
        })
        .onPageBegin((event): void => { if (this.active && event) { this.loaded = false; this.params.protocol.begin(event.url); } })
        .onPageEnd((event): void => { if (this.active && event) { this.loaded = this.params.protocol.allowed(event.url); } })
        .onErrorReceive((event): void => { if (event?.request.isMainFrame()) { this.failed = true; this.loaded = false; } })
        .onHttpErrorReceive((event): void => { if (event?.request.isMainFrame()) { this.failed = true; this.loaded = false; } })
        .onSslErrorEvent((event: SslErrorEvent): void => { event.handler.handleCancel(); this.failed = true; this.loaded = false; })
        .onSslErrorEventReceive((event): void => { event.handler.handleCancel(); this.failed = true; this.loaded = false; })
        .onRenderExited((): void => { this.failed = true; this.loaded = false; })
        .width('100%').layoutWeight(1)
      if (this.failed) {
        Text($r('app.string.mp_line_registration_error')).padding(12)
        Button($r('app.string.mp_line_registration_retry')).onClick((): void => {
          if (this.params.active()) { this.failed = false; this.controller.refresh(); }
        })
      }
      if (this.params.kind === 'country') {
        Text($r('app.string.mp_line_registration_country_choice')).padding(12)
        Row({ space: 12 }) {
          Button($r('app.string.mp_line_registration_decline')).enabled(this.loaded && !this.failed)
            .onClick((): void => this.complete(RegistrationWebResult.DECLINED))
          Button($r('app.string.mp_line_registration_accept')).enabled(this.loaded && !this.failed)
            .onClick((): void => this.complete(RegistrationWebResult.ACCEPTED))
        }.padding(12)
      }
    }.width('100%').height('100%').padding(this.insets).backgroundColor(Color.White)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
  }
}
