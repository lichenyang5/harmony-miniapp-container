import { VK_VENDOR_ID } from './VkVendor';
import { BridgeContext, MiniAppSession } from '../../core/Runtime';
import { MiniAppError } from '../../core/MiniAppError';
import { SYSTEM_ERROR } from '../../core/MiniAppErrorCode';
import { SdkLogContext, SdkLogger } from '../../logging/SdkLogger';
import { VkEventRegistry } from './events/VkEventRegistry';
import { VkEventRegistration } from './events/VkEvent';
import { VkBridgeProtocol, VkBridgeRequest } from './VkBridgeProtocol';
import { InterceptResult } from './InterceptResult';
import { VkMiniAppIdentity } from './VkMiniAppIdentity';
import { VkLaunchParams } from './VkLaunchParams';
import { VK_WEB_APP_CLOSE } from './handlers/VkCloseHandler';
import { assertHostForeground } from '../../core/HostLifecycleMonitor';

// 保留原有导入路径；公共结果定义独立存放，避免装饰器依赖代理。
export { InterceptResult } from './InterceptResult';

const TAG: string = 'VkBridgeProxy';

export class VkBridgeProxy {
  private session?: MiniAppSession;
  private readonly registry: VkEventRegistry;
  private documentGeneration: number = 0;
  private readonly miniAppIdentity?: VkMiniAppIdentity;
  private readonly launchParams?: VkLaunchParams;

  constructor(session: MiniAppSession, registry: VkEventRegistry, miniAppIdentity?: VkMiniAppIdentity,
    launchParams?: VkLaunchParams) {
    this.session = session;
    this.registry = registry;
    this.miniAppIdentity = miniAppIdentity;
    this.launchParams = launchParams;
    // 每个页面只挂一个清理回调，不为每次请求累积闭包。
    this.watchDocument(session);
  }

  /**
   * 返回支持的接口，安卓注入对象需要使用
   */
  supportedHandlers(): string[] {
    return this.registry.getAvailableHandlers();
  }

  /** 仅更新当前会话的入口别名映射，不参与 VK 请求/响应协议。 */
  onMiniAppIdentified(hostUrl: string, appId: string): boolean {
    if (!this.session || !this.registry.isActiveFor(this.session) || typeof hostUrl !== 'string') {
      return false;
    }
    const accepted: boolean = this.miniAppIdentity?.identify(hostUrl, appId) ?? false;
    SdkLogger.info(TAG, 'miniAppIdentityReported', {
      sessionId: this.session.id, documentId: this.session.getDocumentId(),
      code: accepted ? 'IDENTITY_ACCEPTED' : 'IDENTITY_REJECTED'
    });
    return accepted;
  }

  /** iframe 参数由顶层监听校验来源后转交；不记录参数内容。 */
  onMiniAppLaunchParams(hostUrl: string, dataJson: string): boolean {
    const session = this.session;
    if (!session || !this.registry.isActiveFor(session)) {
      return false;
    }
    const accepted: boolean = this.launchParams?.update(hostUrl, dataJson) ?? false;
    SdkLogger.info(TAG, 'launchParamsReported', {
      sessionId: session.id,
      documentId: session.getDocumentId(),
      vendorId: VK_VENDOR_ID,
      code: accepted ? 'LAUNCH_PARAMS_ACCEPTED' : 'LAUNCH_PARAMS_REJECTED'
    });
    return accepted;
  }

  /** VK 顶层 Apps.goBack 的同步入口；失效会话只消费调用。 */
  onHostGoBack(): void {
    const session = this.session;
    if (session === undefined || !this.registry.isActiveFor(session)) {
      return;
    }
    try {
      session.handleHostGoBack();
    } catch (error) {
      SdkLogger.error(TAG, 'hostGoBackFailed', MiniAppError.from(error, SYSTEM_ERROR, '处理 VK 页面返回失败'), {
        sessionId: session.id, vendorId: VK_VENDOR_ID, code: 'HOST_GO_BACK_FAILED'
      });
    }
  }

  /** 顶部关闭按钮直接关闭当前容器，不检查历史栈或侧滑开关。 */
  onHostClose(): void {
    const session = this.session;
    if (session === undefined || !this.registry.isActiveFor(session)) {
      return;
    }
    try {
      assertHostForeground(session.uiAbilityContext);
      session.requestClose();
    } catch (error) {
      SdkLogger.error(TAG, 'hostCloseFailed', MiniAppError.from(error, SYSTEM_ERROR, '处理 VK 顶部关闭失败'), {
        sessionId: session.id, vendorId: VK_VENDOR_ID, code: 'HOST_CLOSE_FAILED'
      });
    }
  }

  onInterceptRequest(dataJson: string, replyId: string): InterceptResult {
    const session = this.session;
    const parsed = VkBridgeProtocol.parseRequest(dataJson);
    if (session === undefined || !this.registry.isActiveFor(session)) {
      // WebView 移除前可能仍有排队的关闭消息，不能在释放代理后转交 VK。
      if (parsed?.method === VK_WEB_APP_CLOSE) {
        return InterceptResult.intercept(0);
      }
      return InterceptResult.pass();
    }
    const request = parsed?.request;
    if (request === undefined) {
      if (parsed?.method === VK_WEB_APP_CLOSE) {
        // 无法可靠解析请求关联信息时只消费消息，不执行关闭，也不放行给 VK。
        SdkLogger.warn(TAG, 'closeEnvelopeRejected', {
          sessionId: session.id,
          vendorId: VK_VENDOR_ID,
          capability: VK_WEB_APP_CLOSE,
          code: 'INVALID_REQUEST'
        });
        return InterceptResult.intercept(0);
      }
      return InterceptResult.pass();
    }

    const registration = this.registry.getHandler(request.method);
    if (registration) {
      this.dispatch(registration, request, replyId);
      return InterceptResult.intercept(registration.timeout);
    }

    SdkLogger.debug(TAG, 'requestPassedThrough', {
      sessionId: session.id, vendorId: VK_VENDOR_ID, capability: request.method
    });
    return InterceptResult.pass();
  }

  onInterceptResponse(dataJson: string): InterceptResult {
    const session = this.session;
    if (session === undefined || !this.registry.isActiveFor(session)) {
      return InterceptResult.pass();
    }
    const response = VkBridgeProtocol.parseResponse(dataJson);
    if (response === undefined) {
      return InterceptResult.pass();
    }
    const interceptor = this.registry.getResponseInterceptor(response.type);
    if (interceptor === undefined) {
      return InterceptResult.pass();
    }
    const logContext: SdkLogContext = {
      sessionId: session.id,
      vendorId: VK_VENDOR_ID,
      documentId: session.getDocumentId(),
      capability: response.type
    };
    try {
      const result = interceptor(response);
      if (result.intercept) {
        SdkLogger.debug(TAG, 'responseIntercepted', logContext);
      } else if (result.data !== undefined) {
        SdkLogger.debug(TAG, 'responseModified', logContext);
      }
      return result;
    } catch (error) {
      SdkLogger.error(TAG, 'responseInterceptorFailed',
        MiniAppError.from(error, SYSTEM_ERROR, 'VK 响应拦截失败'), logContext);
    }
    // 原始 JSON 对应的网页消息未被修改，失败或放行不交付局部修改。
    return InterceptResult.pass();
  }

  /** 会话关闭后切断引用，旧页面残留代理无法继续调用 Runtime。 */
  dispose(): void {
    this.launchParams?.clear();
    if (this.session === undefined) {
      return;
    }
    SdkLogger.info(TAG, 'proxyDisposed', { sessionId: this.session.id, vendorId: VK_VENDOR_ID });
    this.session = undefined;
  }

  onDocumentChanged(): void {
    this.launchParams?.clear();
    this.documentGeneration++;
    if (this.session) {
      this.watchDocument(this.session);
    }
  }

  /** 执行已匹配的事件回调，并在原页面仍有效时回传协议结果。 */
  private async dispatch(registration: VkEventRegistration, request: VkBridgeRequest, replyId: string): Promise<void> {
    const session = this.session;
    if (session === undefined) {
      return;
    }
    const documentId = session.getDocumentId();
    const generation = this.documentGeneration;
    const startedAt = Date.now();
    const logContext: SdkLogContext = {
      sessionId: session.id,
      vendorId: VK_VENDOR_ID,
      documentId,
      requestId: replyId,
      capability: request.method
    };
    SdkLogger.debug(TAG, 'requestStarted', logContext);
    let responseJson: string;
    try {
      const result = await registration.callback(request.params);
      responseJson = JSON.stringify(VkBridgeProtocol.success(registration.resultEvent, request.requestId, result));
      logContext.durationMs = Date.now() - startedAt;
      SdkLogger.debug(TAG, 'requestCompleted', logContext);
    } catch (error) {
      const failure = MiniAppError.from(error, SYSTEM_ERROR, '执行原生能力失败');
      logContext.durationMs = Date.now() - startedAt;
      SdkLogger.error(TAG, 'requestFailed', failure, logContext);
      try {
        responseJson = JSON.stringify(VkBridgeProtocol.failure(registration.failureEvent, request.requestId, failure));
      } catch (_) {
        responseJson =
          JSON.stringify(VkBridgeProtocol.failure(registration.failureEvent, request.requestId, undefined));
      }
    }
    if (this.session !== session || session.getDocumentId() !== documentId ||
      this.documentGeneration !== generation || !this.registry.isActiveFor(session)) {
      SdkLogger.warn(TAG, 'responseDropped', logContext);
      return;
    }
    try {
      const sent = await session.send(
        `window.atomicBridge.postResponse(${JSON.stringify(replyId)}, ${responseJson})`);
      if (!sent) {
        SdkLogger.warn(TAG, 'responseNotSent', logContext);
      }
    } catch (error) {
      SdkLogger.error(TAG, 'responseSendFailed',
        MiniAppError.from(error, SYSTEM_ERROR, 'VK 回包失败'), logContext);
    }
  }

  private watchDocument(session: BridgeContext): void {
    session.addCleanup((): void => {
      this.launchParams?.clear();
      this.documentGeneration++;
    });
  }
}
