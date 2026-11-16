/** 容器收到的原始资源请求；documentId 仅在所属挂载内有效。 */
export interface WebRequest {
  readonly url: string;
  readonly isMainFrame: boolean;
  readonly resource: WebResourceRequest;
  readonly documentId: number;
}

/** 同步分发结果。PASS 停止链并交回 WebView，BLOCK 返回拒绝响应。 */
export class WebRequestDecision {
  static readonly PASS: WebRequestDecision = new WebRequestDecision();
  static readonly BLOCK: WebRequestDecision = new WebRequestDecision();
  readonly response?: WebResourceResponse;

  private constructor(response?: WebResourceResponse) {
    this.response = response;
  }

  static respond(response: WebResourceResponse): WebRequestDecision {
    return new WebRequestDecision(response);
  }
}

export interface WebRequestChain {
  /** 仅在本次同步 handle 内允许调用一次；链末尾为 PASS。 */
  proceed(): WebRequestDecision;
}

export interface WebRequestHandler<T extends WebRequest> {
  readonly id: string;
  supports(request: T): boolean;
  handle(request: T, chain: WebRequestChain): WebRequestDecision;
  reset?(): void;
  dispose?(): void;
}

/** 每次挂载调用一次，不能跨容器共享有状态的处理器实例。 */
export type WebRequestHandlerFactory = () => WebRequestHandler<WebRequest>[];
