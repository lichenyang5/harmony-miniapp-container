import { url } from '@kit.ArkTS';
import { MiniAppSession, SessionWebSchemeRequest } from '../../../core/Runtime';
import { WebSchemeChain, WebSchemeDecision, WebSchemeHandler } from '../../../web/scheme/WebSchemeTypes';
import { SdkLogger } from '../../../logging/SdkLogger';
import { LineAppState } from '../LineAppState';
import { LineAdapter } from '../LineAdapter';
import { LineErrorCode } from '../LineErrorCode';
import { LINE_LIFF_SCHEME, LineLiffCommand } from './LineSchemeConstants';
import { LineMode } from '../LineMode';

/** Binding 保留业务状态与共享窗口控制器，协议仅通过这些端口操作。 */
export interface LineLiffSchemePorts {
  readonly session: MiniAppSession;
  readonly isChild: boolean;
  establishAppState: (state: LineAppState) => void;
  openSubWindow: (address: string) => void;
}

type LineLiffCommandHandler = (request: SessionWebSchemeRequest, chain: WebSchemeChain) => WebSchemeDecision;

export class LineLiffSchemeHandler implements WebSchemeHandler<SessionWebSchemeRequest> {
  readonly id: string = 'line.liff';
  private readonly ports: LineLiffSchemePorts;
  private readonly commands: Map<string, LineLiffCommandHandler> = new Map();
  private readonly commandPattern: RegExp = new RegExp('^' + LINE_LIFF_SCHEME + '://([^/?#]*)(?=[/?#]|$)', 'i');
  private readonly closePattern: RegExp =
    new RegExp('^' + LINE_LIFF_SCHEME + '://' + LineLiffCommand.CLOSE + '/*(?:[?#]|$)', 'i');
  private disposed: boolean = false;

  constructor(ports: LineLiffSchemePorts, mode: LineMode = LineMode.CLIENT) {
    this.ports = ports;
    this.commands.set(LineLiffCommand.APP, (request: SessionWebSchemeRequest): WebSchemeDecision =>
    this.handleApp(request));
    this.commands.set(LineLiffCommand.CLOSE, (request: SessionWebSchemeRequest, chain: WebSchemeChain): WebSchemeDecision => {
      // APK close 命令要求没有路径段，查询参数和 fragment 不影响关闭。
      if (!this.closePattern.test(request.url)) {
        return chain.proceed();
      }
      this.log('liffCloseRequested', request, this.ports.isChild ? 'CHILD_CLOSE' : 'ROOT_CLOSE');
      this.ports.session.requestClose();
      return WebSchemeDecision.CONSUME;
    })
    if (mode !== LineMode.CLIENT) {
      return
    }
    this.commands.set(LineLiffCommand.SUBWINDOW, (request: SessionWebSchemeRequest): WebSchemeDecision => {
      this.ports.openSubWindow(request.url);
      return WebSchemeDecision.CONSUME;
    });

  }

  supports(request: SessionWebSchemeRequest): boolean {
    return request.url.toLowerCase().startsWith(LINE_LIFF_SCHEME + ':');
  }

  handle(request: SessionWebSchemeRequest, chain: WebSchemeChain): WebSchemeDecision {
    // scheme 按 URI 规则忽略大小写；原始 authority 精确匹配，不能将用户名、端口或 APP 当作 app。
    const authority: RegExpMatchArray | null = request.url.match(this.commandPattern);
    const command: LineLiffCommandHandler | undefined = authority ? this.commands.get(authority[1]) : undefined;
    this.log('liffNavigationReceived', request, authority?.[1] === LineLiffCommand.APP ? 'APP' :
      authority?.[1] === LineLiffCommand.SUBWINDOW ? 'SUBWINDOW' : 'OTHER');
    if (!command) {
      this.log('liffNavigationPassed', request, 'UNHANDLED_ROUTE');
      return chain.proceed();
    }
    const session = this.ports.session;
    if (this.disposed || session.isClosed() || request.documentId !== session.getDocumentId()) {
      return WebSchemeDecision.BLOCK;
    }
    if (!request.isMainFrame) {
      this.reject(request, LineErrorCode.APP_SUBFRAME);
      return WebSchemeDecision.BLOCK;
    }
    if (authority?.[1] !== LineLiffCommand.APP && !session.lifecycle.isForeground()) {
      return WebSchemeDecision.BLOCK;
    }
    return command(request, chain);
  }

  dispose(): void {
    this.disposed = true;
  }

  private handleApp(request: SessionWebSchemeRequest): WebSchemeDecision {
    let state: LineAppState;
    try {
      // 只有 app 命令在此解析；subwindow 由窗口控制器校验，close 无需解析。
      const parsed = new url.URL(request.url);
      const segments: string[] = parsed.pathname.split('/').filter((part: string): boolean => part.length > 0);
      const featureToken: string | null = parsed.params.get('feature_token');
      if (segments.length === 0 || featureToken === null || featureToken.length === 0) {
        this.reject(request, LineErrorCode.APP_INVALID_ARGUMENT);
        return WebSchemeDecision.BLOCK;
      }
      state = { liffId: decodeURIComponent(segments[0]), featureToken };
    } catch (_) {
      this.reject(request, LineErrorCode.APP_INVALID_ARGUMENT);
      return WebSchemeDecision.BLOCK;
    }
    const session = this.ports.session;
    if (state.liffId !== (session.getAdapter<LineAdapter>().getLiffId(session) ?? session.appId)) {
      this.reject(request, LineErrorCode.APP_SWITCH_NOT_SUPPORTED);
      return WebSchemeDecision.BLOCK;
    }
    this.ports.establishAppState(state);
    return WebSchemeDecision.CONSUME;
  }

  private reject(request: SessionWebSchemeRequest, code: string): void {
    SdkLogger.warn('LineBridge', 'appNavigationRejected', {
      sessionId: this.ports.session.id, documentId: request.documentId, code
    });
  }

  private log(event: string, request: SessionWebSchemeRequest, code: string): void {
    SdkLogger.info('LineBridge', event, {
      sessionId: this.ports.session.id, documentId: request.documentId, code
    });
  }
}
