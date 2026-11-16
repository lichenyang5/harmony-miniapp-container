import { MiniAppContainer, MiniAppInfo, MiniAppError, MiniAppNavigationController,
  VendorAdapter, LineAdapter, LineMode, VkAdapter } from 'mpsdk';
import { createLaunchInfo, DemoMiniApp, isDemoMiniApp } from '../model/MiniAppCatalog';
import BuildProfile from 'BuildProfile';
import { lineBridgeDiagnostics } from '../model/LineBridgeDiagnostics';
import { util } from '@kit.ArkTS';
import { vkTransitionIcon } from '../model/VkTransitionIcon';

@Entry
@ComponentV2
struct MiniAppPage {
  @Local private app: MiniAppInfo | undefined = undefined;
  @Local private title: string = '';
  @Local private ready: boolean = false;
  @Local private errorCode: string = '';
  private adapter: VendorAdapter | undefined = undefined;
  private navigation: MiniAppNavigationController | undefined = undefined;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    const params = this.getUIContext().getRouter().getParams() as DemoMiniApp;
    if (!isDemoMiniApp(params)) { this.errorCode = 'INVALID_LAUNCH'; return; }
    this.title = params.name;
    this.adapter = params.vendor === 'line' ? new LineAdapter({ mode: LineMode.WEB }) : new VkAdapter();
    const app = createLaunchInfo(params);
    // Keep diagnostics on the API test app, away from business mini app pages.
    if (BuildProfile.DEBUG && params.vendor === 'line' && params.appId === '2012241484-PibjtMII') {
      app.jsOnDocEnd = lineBridgeDiagnostics(params.appId);
    }
    if (params.vendor === 'vk') {
      const context = this.getUIContext().getHostContext();
      if (context) {
        const image = context.resourceManager.getMediaContentSync($r('app.media.login_transition_icon').id);
        const dataUrl = 'data:image/png;base64,' + new util.Base64Helper().encodeToStringSync(image);
        app.jsOnDocStart = vkTransitionIcon(params.appId, dataUrl);
      }
    }
    this.app = app;
  }

  aboutToDisappear(): void {
    this.active = false;
    this.navigation = undefined;
    this.ready = false;
  }

  private close(): void {
    if (!this.active) return;
    this.active = false;
    this.app = undefined;
    this.navigation = undefined;
    this.getUIContext().getRouter().back();
  }

  onBackPress(): boolean {
    try {
      if (this.navigation?.handleBackPress()) return true;
    } catch (_) { this.errorCode = 'NAVIGATION_FAILED'; return true; }
    this.close();
    return true;
  }

  private back(): void {
    try {
      if (!this.navigation?.goBack()) this.close();
    } catch (_) { this.errorCode = 'NAVIGATION_FAILED'; }
  }

  private refresh(): void {
    try { this.navigation?.refresh(); } catch (_) { this.errorCode = 'NAVIGATION_FAILED'; }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button($r('app.string.mp_host_back')).onClick(() => this.back())
        Text(this.title).fontSize(16).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Button($r('app.string.mp_host_refresh')).enabled(this.ready).onClick(() => this.refresh())
        Button($r('app.string.mp_host_close')).onClick(() => this.close())
      }.padding(8).width('100%')
      if (this.errorCode) {
        Text($r('app.string.mp_host_container_failed', this.errorCode)).fontSize(13).padding(12)
      }
      if (this.app) {
        MiniAppContainer({
          app: this.app, adapter: this.adapter,
          onNavigationReady: (controller: MiniAppNavigationController): void => {
            if (!this.active) return;
            this.navigation = controller;
            controller.enableBackPressHandling();
            this.ready = true;
          },
          onError: (error: MiniAppError): void => {
            if (!this.active) return;
            this.ready = false;
            this.navigation = undefined;
            this.errorCode = error.code;
          },
          onClose: (): void => this.close()
        }).layoutWeight(1).width('100%')
      }
    }.width('100%').height('100%')
  }
}
