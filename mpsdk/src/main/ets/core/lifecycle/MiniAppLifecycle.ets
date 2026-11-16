/** 会话与 WebView 绑定、宿主选中和 UIAbility 前台状态共同决定的生命周期。 */
export enum MiniAppLifecycleState {
  CREATED = 'CREATED',
  FOREGROUND = 'FOREGROUND',
  BACKGROUND = 'BACKGROUND',
  DESTROYED = 'DESTROYED'
}

/** 状态已提交后交付的实际变化。 */
export interface MiniAppLifecycleChange {
  readonly previous: MiniAppLifecycleState;
  readonly current: MiniAppLifecycleState;
}

/** 消费者只读端口；observe 不立即发送当前状态。 */
export interface MiniAppLifecycle {
  getState(): MiniAppLifecycleState;
  isForeground(): boolean;
  observe(listener: (change: MiniAppLifecycleChange) => void): () => void;
}
