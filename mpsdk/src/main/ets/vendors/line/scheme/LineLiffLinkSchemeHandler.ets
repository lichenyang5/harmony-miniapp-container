import { MiniAppInfo } from '../../../core/MiniAppOptions';
import { MiniAppError } from '../../../core/MiniAppError';
import { MiniAppSession, SessionWebSchemeRequest } from '../../../core/Runtime';
import { SdkLogger } from '../../../logging/SdkLogger';
import { WebSchemeChain, WebSchemeDecision, WebSchemeHandler } from '../../../web/scheme/WebSchemeTypes';
import { validateLineBrowserUrl } from '../browser/LineBrowserUrl';
import { LINE_VENDOR_ID } from '../LineConstants';
import { LineErrorCode } from '../LineErrorCode';
import { LineAdapter } from '../LineAdapter';
import { resolveLineLiffUrl } from '../liff/LineLiffUrl';
import { LINE_HTTP_SCHEME, LINE_HTTPS_SCHEME, LINE_LIFF_HOST, LINE_MINIAPP_HOST } from './LineSchemeConstants';

export interface LineLiffLinkSchemePorts {
  readonly session: MiniAppSession;
  canTransition: () => boolean;
}

/** HTTP(S) 的 LIFF 链接统一匹配和处理，每个会话只创建一个实例。 */
export class LineLiffLinkSchemeHandler implements WebSchemeHandler<SessionWebSchemeRequest> {
  readonly id: string = 'line.liff.link';
  private readonly ports: LineLiffLinkSchemePorts;
  private pending: boolean = false;
  private generation: number = 0;
  private disposed: boolean = false;

  constructor(ports: LineLiffLinkSchemePorts) {
    this.ports = ports;
  }

  supports(request: SessionWebSchemeRequest): boolean {
    const authority = request.url.match(/^https?:\/\/([^/?#\\]+)/i)?.[1].toLowerCase().replace(/:\d+$/, '');
    return authority === LINE_LIFF_HOST || authority === LINE_MINIAPP_HOST;
  }

  handle(request: SessionWebSchemeRequest, chain: WebSchemeChain): WebSchemeDecision {
    let target: MiniAppInfo;
    try {
      const parsed = validateLineBrowserUrl(request.url);
      // 与 navigateTo 的入口限制一致，非默认端口不能变成原生启动目标。
      if (parsed.port) {
        return WebSchemeDecision.BLOCK;
      }
      if (parsed.protocol === LINE_HTTP_SCHEME + ':') {
        parsed.protocol = LINE_HTTPS_SCHEME + ':';
      }
      const link = resolveLineLiffUrl(request.url, parsed);
      if (!link) {
        return chain.proceed();
      }
      target = { appId: link.appId, vendor: LINE_VENDOR_ID, url: link.url };
    } catch (_) {
      return WebSchemeDecision.BLOCK;
    }
    const session = this.ports.session;
    if (this.disposed || session.isClosed() || request.documentId !== session.getDocumentId()) {
      return WebSchemeDecision.BLOCK;
    }
    if (!this.ports.canTransition()) {
      return chain.proceed();
    }
    if (!request.isMainFrame) {
      return WebSchemeDecision.BLOCK;
    }
    // 启动／重定向期间，同一应用的入口由已有加载流程处理，避免再次原生启动。
    const isCurrentApp: boolean = target.appId === session.appId ||
      target.appId === session.getAdapter<LineAdapter>().getLiffId(session);
    if (isCurrentApp && !session.isDocumentFinished(request.documentId)) {
      return chain.proceed();
    }
    if (!session.lifecycle.isForeground() || this.pending) {
      return WebSchemeDecision.BLOCK;
    }
    this.pending = true;
    this.open(target, request.documentId, this.generation);
    return WebSchemeDecision.CONSUME;
  }

  reset(): void {
    this.generation++;
    this.pending = false;
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.reset();
  }

  private async open(target: MiniAppInfo, documentId: number, generation: number): Promise<void> {
    try {
      await this.ports.session.requestOpenMiniApp(target);
    } catch (error) {
      if (!this.disposed && generation === this.generation &&
        !this.ports.session.isClosed() && documentId === this.ports.session.getDocumentId() &&
        this.ports.session.lifecycle.isForeground()) {
        const failure = MiniAppError.from(error as Object, LineErrorCode.DIRECT_NAVIGATION_FAILED,
          'Unable to open the target LINE mini app');
        SdkLogger.warn('LineBridge', 'directNavigationFailed', {
          sessionId: this.ports.session.id, documentId, code: failure.code
        });
      }
    } finally {
      if (generation === this.generation) {
        this.pending = false;
      }
    }
  }
}
