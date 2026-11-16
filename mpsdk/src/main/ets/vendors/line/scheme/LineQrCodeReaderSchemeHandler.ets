import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { scanCore } from '@kit.ScanKit';
import { CodeReaderTools } from '../../../capabilities/media/CodeReaderTools';
import { ClipboardTools } from '../../../capabilities/clipboard/ClipboardTools';
import { MiniAppError } from '../../../core/MiniAppError';
import { MiniAppOpenHandler } from '../../../core/MiniAppOptions';
import { USER_CANCELLED } from '../../../core/MiniAppErrorCode';
import { SdkLogger } from '../../../logging/SdkLogger';
import { WebSchemeChain, WebSchemeDecision, WebSchemeHandler, WebSchemeRequest } from '../../../web/scheme/WebSchemeTypes';
import { validateLineBrowserUrl } from '../browser/LineBrowserUrl';
import { LineBrowserHost } from '../browser/LineBrowserHost';
import { LineErrorCode } from '../LineErrorCode';
import { LineMode } from '../LineMode';
import { LineScanResultDialogHost } from '../scan/LineScanResultDialogHost';
import { LineScanResultAction } from '../scan/LineScanResultTypes';
import { resolveLineAppSchemeUrl } from './LineAppSchemeUrl';
import {
  LINE_APP_SCHEME, LINE_FEATURE_HOST, LINE_HTTPS_SCHEME, LINE_NATIVE_VIEW_HOST,
  LINE_QR_READER_HTTP_PATH, LINE_QR_READER_PATH
} from './LineSchemeConstants';

export interface LineQrCodeReaderPorts<T extends WebSchemeRequest> {
  isCurrent: (request: T) => boolean;
  openMiniApp: MiniAppOpenHandler;
}

/**
 * APK 在 CameraScannerActivity 内展示结果，用户点击后操作。
 * SDK 复用系统扫码页；WEB/WEB_HOOK 扩展深链打开，CLIENT 保留结果 Dialog，不分享、不向网页回包。
 * 这是全局 nv URL 入口，不是 LIFF Bridge 方法，不额外增加 featureToken 授权门槛。
 */
export class LineQrCodeReaderSchemeHandler<T extends WebSchemeRequest> implements WebSchemeHandler<T> {
  readonly id: string = 'line.qrcode.reader';
  private readonly context: common.UIAbilityContext;
  private readonly ports: LineQrCodeReaderPorts<T>;
  private readonly mode: LineMode;
  private readonly reader: CodeReaderTools;
  private readonly dialog: LineScanResultDialogHost;
  private readonly browser: LineBrowserHost;
  private generation: number = 0;
  private pending: boolean = false;
  private disposed: boolean = false;

  constructor(context: common.UIAbilityContext, ports: LineQrCodeReaderPorts<T>, mode: LineMode = LineMode.CLIENT) {
    this.context = context;
    this.ports = ports;
    this.mode = mode;
    this.reader = new CodeReaderTools(context);
    this.dialog = new LineScanResultDialogHost(context);
    this.browser = new LineBrowserHost(context, ports.openMiniApp);
  }

  supports(request: T): boolean {
    const route = request.url.match(/^([a-z]+):\/\/([^/?#]*)([^?#]*)(?:[?#][\s\S]*)?$/i);
    if (!route || /[\u0000-\u0020\u007f\\]/.test(request.url)) {
      return false;
    }
    const scheme: string = route[1].toLowerCase();
    const path: string = route[3].endsWith('/') ? route[3].slice(0, -1) : route[3];
    return (scheme === LINE_HTTPS_SCHEME && route[2].toLowerCase() === LINE_FEATURE_HOST &&
      path === LINE_QR_READER_HTTP_PATH) ||
      (scheme === LINE_APP_SCHEME && route[2] === LINE_NATIVE_VIEW_HOST && path === LINE_QR_READER_PATH);
  }

  handle(request: T, _chain: WebSchemeChain): WebSchemeDecision {
    if (this.disposed || this.pending || !request.isMainFrame || !this.ports.isCurrent(request)) {
      return WebSchemeDecision.BLOCK;
    }
    this.pending = true;
    this.scan(request, this.generation);
    return WebSchemeDecision.CONSUME;
  }

  reset(): void {
    this.generation++;
    this.pending = false;
    this.dialog.dismiss();
    this.browser.dismissAll();
  }

  dispose(): void {
    this.disposed = true;
    this.reset();
    this.reader.dispose();
    this.browser.dispose();
  }

  private current(request: T, generation: number): boolean {
    return !this.disposed && generation === this.generation && this.ports.isCurrent(request);
  }

  private async scan(request: T, generation: number): Promise<void> {
    try {
      const value: string = await this.reader.read(scanCore.ScanType.QR_CODE);
      if (!this.current(request, generation)) {
        return;
      }
      if (this.mode === LineMode.WEB || this.mode === LineMode.WEB_HOOK) {
        const target = resolveLineAppSchemeUrl(value);
        if (target) {
          await this.ports.openMiniApp(target);
          return;
        }
      }
      let isLink: boolean = false;
      try {
        validateLineBrowserUrl(value);
        isLink = true;
      } catch (_) { /* 其他 scheme、普通文字和无效 URL 都只按文本展示，不执行。 */
      }
      const action = await this.dialog.show(value, isLink, (): boolean => this.current(request, generation));
      if (!this.current(request, generation)) {
        return;
      }
      if (action === LineScanResultAction.OPEN && isLink) {
        await this.browser.open(value);
      } else if (action === LineScanResultAction.COPY) {
        await ClipboardTools.writeText(value);
        if (this.current(request, generation)) {
          await this.toast($r('app.string.mp_line_scan_result_copied'), request, generation);
        }
      }
    } catch (error) {
      if (this.current(request, generation) &&
        !(error instanceof MiniAppError && error.code === USER_CANCELLED)) {
        SdkLogger.warn('LineQrCodeReader', 'operationFailed', { code: LineErrorCode.QR_READER_FAILED });
        await this.toast($r('app.string.mp_line_scan_result_failed'), request, generation);
      }
    } finally {
      if (generation === this.generation) {
        this.pending = false;
      }
    }
  }

  private async toast(message: Resource, request: T, generation: number): Promise<void> {
    try {
      const host = await window.getLastWindow(this.context);
      if (this.current(request, generation)) {
        host.getUIContext().getPromptAction().showToast({ message });
      }
    } catch (_) { /* 提示失败不重新触发扫码或产生未处理的异步异常。 */
    }
  }
}
