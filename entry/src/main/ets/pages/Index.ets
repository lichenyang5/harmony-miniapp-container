import { util } from '@kit.ArkTS';
import { DemoMiniApp, parseCatalog } from '../model/MiniAppCatalog';

@Entry
@ComponentV2
struct Index {
  @Local private apps: DemoMiniApp[] = [];
  @Local private loading: boolean = true;
  @Local private failed: boolean = false;
  private active: boolean = false;

  aboutToAppear(): void { this.active = true; this.loadCatalog(); }
  aboutToDisappear(): void { this.active = false; }

  private async loadCatalog(): Promise<void> {
    this.loading = true;
    this.failed = false;
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('Host unavailable');
      const contents = await context.resourceManager.getRawFileContent('miniapps.json');
      const apps = parseCatalog(util.TextDecoder.create('utf-8').decodeToString(contents));
      if (this.active) this.apps = apps;
    } catch (_) {
      if (this.active) this.failed = true;
    } finally {
      if (this.active) this.loading = false;
    }
  }

  private async open(app: DemoMiniApp): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/MiniAppPage', params: app });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.mp_host_open_failed') });
    }
  }

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.mp_host_title')).fontSize(28).fontWeight(FontWeight.Bold)
      Text($r('app.string.mp_host_scope')).fontSize(14).fontColor('#526078')
      Text($r('app.string.mp_host_pending')).fontSize(13).fontColor('#8A5200')
      if (this.loading) {
        LoadingProgress().width(40).height(40)
      } else if (this.failed) {
        Text($r('app.string.mp_host_catalog_failed'))
        Button($r('app.string.mp_host_retry')).onClick(() => this.loadCatalog())
      } else {
        List({ space: 12 }) {
          ForEach(this.apps, (app: DemoMiniApp) => {
            ListItem() {
              Column({ space: 8 }) {
                Text(app.name).fontSize(20).fontWeight(FontWeight.Medium)
                Text(app.vendor === 'line' ? $r('app.string.mp_host_line_scope') :
                  $r('app.string.mp_host_vk_scope')).fontSize(14).fontColor('#526078')
                Button($r('app.string.mp_host_open')).onClick(() => this.open(app))
              }.alignItems(HorizontalAlign.Start).padding(20).width('100%')
              .backgroundColor('#F1F5FC').borderRadius(16)
            }
          }, (app: DemoMiniApp): string => app.vendor + ':' + app.appId)
        }.layoutWeight(1).width('100%')
      }
    }.padding(24).width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }
}
