import { MiniAppInfo, MiniAppOpenHandler } from '../../../core/MiniAppOptions';
import { SdkLogger } from '../../../logging/SdkLogger';
import { WebSchemeChain, WebSchemeDecision, WebSchemeHandler, WebSchemeRequest } from '../../../web/scheme/WebSchemeTypes';
import { LINE_VENDOR_ID } from '../LineConstants';
import { LineErrorCode } from '../LineErrorCode';
import { LINE_APP_SCHEME, LINE_LIFF_APP_URL_PREFIX, LineLiffCommand } from './LineSchemeConstants';

export interface LineBrowserAppSchemePorts {
  isActive: () => boolean;
  openMiniApp: MiniAppOpenHandler;
  onFailure: () => void;
}

/** 网页深链只转交启动目标；不接受 featureToken，不依赖小程序 Session。 */
export class LineBrowserAppSchemeHandler implements WebSchemeHandler<WebSchemeRequest> {
  readonly id: string = 'line.browser.app';
  private readonly ports: LineBrowserAppSchemePorts;
  private readonly pattern: RegExp = new RegExp('^' + LINE_APP_SCHEME + '://([^/?#]*)([\\s\\S]*)$', 'i');
  private generation: number = 0;
  private pending: boolean = false;
  private disposed: boolean = false;

  constructor(ports: LineBrowserAppSchemePorts) {
    this.ports = ports;
  }

  supports(request: WebSchemeRequest): boolean {
    return request.url.toLowerCase().startsWith(LINE_APP_SCHEME + ':');
  }

  handle(request: WebSchemeRequest, chain: WebSchemeChain): WebSchemeDecision {
    const route: RegExpMatchArray | null = request.url.match(this.pattern);
    if (!route || route[1] !== LineLiffCommand.APP) {
      return chain.proceed();
    }
    if (this.disposed || !this.ports.isActive() || !request.isMainFrame || this.pending) {
      return WebSchemeDecision.BLOCK;
    }
    let target: MiniAppInfo;
    try {
      const path: RegExpMatchArray | null = route[2].match(/^\/([^/?#]+)([?#].*)?$/);
      if (!path || /[\u0000-\u0020\u007f\\]/.test(request.url)) {
        return WebSchemeDecision.BLOCK;
      }
      const appId: string = decodeURIComponent(path[1]);
      if (!appId || /[\s/?#\\\u0000-\u001f\u007f]/.test(appId)) {
        return WebSchemeDecision.BLOCK;
      }
      target = { appId, vendor: LINE_VENDOR_ID, url: LINE_LIFF_APP_URL_PREFIX + path[1] + (path[2] ?? '') };
    } catch (_) {
      return WebSchemeDecision.BLOCK;
    }
    this.pending = true;
    this.open(target, this.generation);
    return WebSchemeDecision.CONSUME;
  }

  reset(): void {
    this.generation++;
    this.pending = false;
  }

  dispose(): void {
    this.disposed = true;
    this.reset();
  }

  private async open(target: MiniAppInfo, generation: number): Promise<void> {
    try {
      await this.ports.openMiniApp(target);
    } catch (_) {
      if (!this.disposed && generation === this.generation && this.ports.isActive()) {
        SdkLogger.warn('LineBrowser', 'miniAppOpenFailed', { code: LineErrorCode.BROWSER_FAILED });
        try {
          this.ports.onFailure();
        } catch (_) { /* 提示失败不产生未处理的异步拒绝。 */
        }
      }
    } finally {
      if (generation === this.generation) {
        this.pending = false;
      }
    }
  }
}
