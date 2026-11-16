import { MiniAppSession } from '../../core/Runtime';
import { SdkLogger } from '../../logging/SdkLogger';
import { LineBridgeProtocol, LineBridgeRequest } from './LineBridgeProtocol';
import { LineEventRegistry } from './LineEventRegistry';
import { LineBridgeError } from './LineBridgeError';
import { LineAppState, LineAppStateProvider } from './LineAppState';
import { LineFeaturePolicy } from './LineFeaturePolicy';
import { LineEventContext } from './LineEventContext';

const TAG: string = 'LineBridgeProxy';

export class LineBridgeProxy {
  readonly name: string = '_liff';
  private session?: MiniAppSession;
  private readonly registry: LineEventRegistry;
  private appStateProvider?: LineAppStateProvider;
  private activeDocumentId: number = -1;

  constructor(registry: LineEventRegistry, session: MiniAppSession, appStateProvider?: LineAppStateProvider) {
    this.registry = registry;
    this.session = session;
    this.appStateProvider = appStateProvider;
  }

  /** 仅供原生内部读取，不在 JS 代理方法列表中。 */
  getAppState(): LineAppState | undefined {
    return this.appStateProvider?.getAppState();
  }

  onDocumentChanged(): void {
    this.activeDocumentId = -1;
  }

  onPageFinished(documentId: number): void {
    if (this.session && this.session.getDocumentId() === documentId && this.registry.isActive()) {
      this.activeDocumentId = documentId;
    }
  }

  postMessage(type: string, featureToken: string, callbackId: string, paramsJson: string): void {
    try {
      const request = LineBridgeProtocol.parseRequest(type, featureToken, callbackId, paramsJson);
      if (request) {
        SdkLogger.debug(TAG, 'requestReceived', {
          sessionId: this.session?.id, capability: request.type
        });
        this.dispatch(request);
      }
    } catch (_) {
      // 未建立可信请求上下文，不构造网页失败事件，也不记录 Token 或 URL。
      SdkLogger.warn(TAG, 'requestContextUnavailable');
    }
  }


  validateFeatureToken(appId: string, featureToken: string): boolean {
    if (!this.session || !this.registry.isActive() ||
      typeof appId !== 'string' || typeof featureToken !== 'string') {
      return false;
    }
    const state = this.getAppState();
    return state !== undefined && state.liffId === appId && state.featureToken === featureToken;
  }

  dispose(): void {
    this.activeDocumentId = -1;
    this.session = undefined;
    this.appStateProvider = undefined;
  }

  private async dispatch(request: LineBridgeRequest): Promise<void> {
    const session = this.session;
    if (!session || !this.registry.isActive()) {
      return;
    }
    const documentId: number = session.getDocumentId();
    if (this.activeDocumentId !== documentId) {
      SdkLogger.debug(TAG, 'requestIgnored', {
        sessionId: session.id,
        documentId,
        capability: request.type,
        data: JSON.stringify({ reason: 'DOCUMENT_NOT_READY' })
      });
      return;
    }
    // 在执行方法前保存关联字段，避免异步操作修改请求对象后改变回包目标。
    const type: string = request.type;
    const callbackId: string = request.callbackId;
    let payload: string;
    const context = new LineEventContext();
    try {
      const tokenError = LineFeaturePolicy.checkToken(request, this.getAppState());
      if (tokenError) {
        const expectedFeatureToken: string | undefined = this.getAppState()?.featureToken;
        SdkLogger.debug(TAG, 'featureTokenMismatch', {
          sessionId: session.id,
          documentId,
          capability: type,
          data: JSON.stringify({
            requestToken: request.featureToken,
            expectedToken: expectedFeatureToken
          })
        });
        throw tokenError;
      }
      const handler = this.registry.getHandler(type);
      if (!handler) {
        // 未注册的已知方法按权限不足处理；未知方法返回无效消息。
        throw this.registry.isKnownMethod(type) ?
          LineBridgeError.permissionDenied(type) : LineBridgeError.invalidMessage(type);
      }
      if (session.lifecycle?.isForeground() === false) {
        throw LineBridgeError.permissionDenied(type);
      }
      SdkLogger.debug(TAG, 'handlerStarted', { sessionId: session.id, documentId, capability: type });
      const result = await handler.handle(request.params, context);
      SdkLogger.debug(TAG, 'handlerCompleted', { sessionId: session.id, documentId, capability: type });
      payload = LineBridgeProtocol.serializeSuccess(type, callbackId, result);
    } catch (error) {
      context.dispose();
      const failure = error instanceof LineBridgeError ? error : LineBridgeError.internal(error as Object);
      SdkLogger.debug(TAG, 'handlerFailed', { sessionId: session.id, documentId, capability: type });

      payload = LineBridgeProtocol.serializeFailure(type, callbackId, failure);
    }

    // 异步处理结束后，只向原来的有效页面提交一次回包。
    if (!this.isCurrentDocument(session, documentId)) {
      context.dispose();
      return;
    }
    const literal: string = JSON.stringify(payload);
    try {
      const delivery = session.send(`if (window.liff && typeof window.liff._dispatchEvent === 'function') {
        window.liff._dispatchEvent(${literal});
      }`);
      context.runAfterReplySubmitted((): boolean => this.isCurrentDocument(session, documentId));
      await delivery;
      SdkLogger.debug(TAG, 'deliveryCompleted', { sessionId: session.id, documentId, capability: type });
    } catch (_) {
      SdkLogger.warn(TAG, 'deliveryFailed', { sessionId: session.id, documentId, code: 'WEB_SCRIPT_FAILED' });
    } finally {
      context.dispose();
    }
  }

  private isCurrentDocument(session: MiniAppSession, documentId: number): boolean {
    return this.registry.isActive() &&
      this.activeDocumentId === documentId && session.getDocumentId() === documentId;
  }
}
