import { SdkLogger } from '../../logging/SdkLogger';

/** 每次请求独立持有；后置动作只在成功回包脚本提交后执行，不等待网页执行完成。 */
export class LineEventContext {
  private actions: Array<() => void> = [];
  private completed: boolean = false;

  afterReplySubmitted(action: () => void): void {
    if (!this.completed) {
      this.actions.push(action);
    }
  }

  /** 分发器调用；动作执行前逐次检查原文档，避免前一动作关闭或切页后继续操作。 */
  runAfterReplySubmitted(isCurrentDocument: () => boolean): void {
    const actions = this.actions;
    this.dispose();
    for (const action of actions) {
      if (!isCurrentDocument()) {
        return;
      }
      try {
        action();
      } catch (_) {
        // 已提交的成功回包不可撤回，也不能因后置动作失败再发送失败回包。
        SdkLogger.warn('LineEventContext', 'afterReplyFailed');
      }
    }
  }

  /** 失败或过期请求丢弃动作；完成后忽略迟到的注册。 */
  dispose(): void {
    this.completed = true;
    this.actions = [];
  }
}
