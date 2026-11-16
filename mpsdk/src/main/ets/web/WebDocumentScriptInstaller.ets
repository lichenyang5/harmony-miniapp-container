import { FrameCallback, UIContext } from '@kit.ArkUI';
import { DocumentScript } from '../core/Runtime';
import { MiniAppError } from '../core/MiniAppError';
import { DOCUMENT_CHANGED, SESSION_CLOSED, WEB_CONTAINER_FAILED } from '../core/MiniAppErrorCode';

interface ScriptInstallation {
  resolve: () => void;
  reject: (error: MiniAppError) => void;
}

/** onIdle 在本帧渲染后执行；onFrame 本身仍早于组件属性提交。 */
class ScriptInstallationFrame extends FrameCallback {
  private complete?: () => void;

  constructor(complete: () => void) {
    super();
    this.complete = complete;
  }

  onFrame(_time: number): void {
  }

  onIdle(_timeLeft: number): void {
    const complete = this.complete;
    this.complete = undefined;
    complete?.();
  }
}

/** 通过声明式状态安装 Web 文档脚本，等待属性提交后才允许加载。 */
export class WebDocumentScriptInstaller {
  private readonly context: UIContext;
  private readonly apply: (scripts: DocumentScript[]) => void;
  private pending?: ScriptInstallation;
  private disposed: boolean = false;

  constructor(context: UIContext, apply: (scripts: DocumentScript[]) => void) {
    this.context = context;
    this.apply = apply;
  }

  install(scripts: DocumentScript[]): Promise<void> {
    if (this.disposed) {
      return Promise.reject(new MiniAppError(SESSION_CLOSED, 'WebView is closed'));
    }
    this.pending?.reject(new MiniAppError(DOCUMENT_CHANGED, 'Document scripts were replaced'));
    return new Promise<void>((resolve, reject): void => {
      const task: ScriptInstallation = { resolve, reject };
      this.pending = task;
      try {
        this.context.runScopedTask((): void => this.apply(scripts));
        this.context.postFrameCallback(new ScriptInstallationFrame((): void => {
          if (this.pending === task) {
            this.pending = undefined;
            task.resolve();
          }
        }));
      } catch (error) {
        this.pending = undefined;
        task.reject(MiniAppError.from(error as Object, WEB_CONTAINER_FAILED, 'Unable to install document scripts'));
      }
    });
  }

  dispose(): void {
    this.disposed = true;
    const task = this.pending;
    this.pending = undefined;
    task?.reject(new MiniAppError(SESSION_CLOSED, 'WebView is closed'));
  }
}
