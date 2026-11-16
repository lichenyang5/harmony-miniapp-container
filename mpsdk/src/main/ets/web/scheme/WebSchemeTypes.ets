/** 通用 WebView 协议请求；使用者可扩展自己的上下文字段。 */
export interface WebSchemeRequest {
  readonly url: string;
  readonly isMainFrame: boolean;
}

/** 同步协议处理结果：交回 WebView、已处理或阻止。 */
export enum WebSchemeDecision {
  PASS,
  CONSUME,
  BLOCK
}

/** 当前处理器的同步续传入口；只允许在本次 handle 内调用一次。 */
export interface WebSchemeChain {
  /** 从下一个处理器继续匹配原请求，链末尾返回 PASS。 */
  proceed(): WebSchemeDecision;
}

/** 内部 WebView 协议扩展；每个使用者负责创建独立实例并驱动生命周期。 */
export interface WebSchemeHandler<T extends WebSchemeRequest> {
  /** 唯一诊断标识，仅允许 ASCII 字母、数字、点、下划线和短横线。 */
  readonly id: string;

  /** 同步判断是否支持当前请求；只做匹配，不启动操作或修改状态。 */
  supports(request: T): boolean;

  /** 不处理时返回 chain.proceed()；直接返回 PASS 不会自动执行后续处理器。 */
  handle(request: T, chain: WebSchemeChain): WebSchemeDecision;

  /** 使用者上下文失效时清理临时状态，保留注册。 */
  reset?(): void;

  /** 释放处理器持有的资源。 */
  dispose?(): void;
}
