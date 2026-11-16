import { LineErrorCode } from './LineErrorCode';
import { common } from '@kit.AbilityKit';
import { ComponentContent, window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { MiniAppSession } from '../../core/Runtime';
import { MiniAppError } from '../../core/MiniAppError';
import { SdkLogger } from '../../logging/SdkLogger';
import { LineWindowHost } from './LineWindowController';
import { lineDialogBuilder, LineDialogParams } from './LineDialogView';
import { LineSubViewPresentation } from './liff/LineSubViewPresentation';

export interface LineDialogCallbacks {
  requestClose: () => void;
  onFailure: (error: MiniAppError) => void;
  onError: (error: MiniAppError) => void;
}

class LineDialogEntry {
  readonly uiContext: UIContext;
  readonly content: ComponentContent<LineDialogParams>;
  opened: boolean = false;
  released: boolean = false;

  constructor(uiContext: UIContext, content: ComponentContent<LineDialogParams>) {
    this.uiContext = uiContext;
    this.content = content;
  }
}

/** 每个 LINE 主 Binding 独占一个 Dialog 宿主，异步弹出期间也受代次保护。 */
export class LineDialogHost implements LineWindowHost {
  private readonly context: common.UIAbilityContext;
  private readonly callbacks: LineDialogCallbacks;
  private entry?: LineDialogEntry;
  private generation: number = 0;
  private disposed: boolean = false;

  constructor(context: common.UIAbilityContext, callbacks: LineDialogCallbacks) {
    this.context = context;
    this.callbacks = callbacks;
  }

  async show(session: MiniAppSession, headers: webview.WebHeader[] = [],
    presentation: LineSubViewPresentation = {}): Promise<void> {
    if (this.disposed) {
      return;
    }
    this.hide();
    const generation = this.generation;
    // 在等待宿主窗口前复制，避免异步挂载期间外部修改本次展示配置。
    const presentationSnapshot: LineSubViewPresentation = {
      presentationType: presentation.presentationType,
      closeButtonPosition: presentation.closeButtonPosition,
      closeButtonLabel: presentation.closeButtonLabel,
      hideCloseButton: presentation.hideCloseButton
    };
    const hostWindow = await window.getLastWindow(this.context);
    if (this.disposed || generation !== this.generation) {
      return;
    }
    const uiContext = hostWindow.getUIContext();
    const params: LineDialogParams = {
      session,
      hostWindow,
      presentation: presentationSnapshot,
      headers: headers.map((header: webview.WebHeader): webview.WebHeader => ({
        headerKey: header.headerKey, headerValue: header.headerValue
      })),
      requestClose: (): void => {
        if (generation === this.generation && !this.disposed) {
          this.callbacks.requestClose();
        }
      },
      onFailure: (error: MiniAppError): void => {
        if (generation === this.generation && !this.disposed) {
          this.callbacks.onFailure(error);
        }
      }
    };
    const content = new ComponentContent<LineDialogParams>(uiContext, lineDialogBuilder, params);
    const entry = new LineDialogEntry(uiContext, content);
    this.entry = entry;
    try {
      await uiContext.getPromptAction().openCustomDialog(content, {
        // 保持遮罩和子窗口外框稳定，网页视口由 ArkWeb 单独处理键盘。
        keyboardAvoidMode: KeyboardAvoidMode.NONE,
        autoCancel: false,
        isModal: true,
        alignment: DialogAlignment.Bottom,
        onWillDismiss: (action: DismissDialogAction): void => {
          if (this.entry !== entry) {
            action.dismiss();
            return;
          }
          // 交由窗口控制器立即关闭子窗口，再异步提交原生结果收尾。
          this.callbacks.requestClose();
        },
        onDidDisappear: (): void => {
          if (this.entry !== entry) {
            return;
          }
          this.entry = undefined;
          this.release(entry);
          this.callbacks.onFailure(new MiniAppError(LineErrorCode.SUBWINDOW_DISMISSED, 'LINE 子窗口被系统关闭'));
        }
      });
      entry.opened = true;
      if (this.entry !== entry || this.disposed) {
        this.release(entry);
      }
    } catch (error) {
      if (this.entry === entry) {
        this.entry = undefined;
      }
      this.release(entry);
      throw MiniAppError.from(error as Object, LineErrorCode.DIALOG_FAILED, '无法展示 LINE 子窗口');
    }
  }

  hide(): void {
    this.generation++;
    const entry = this.entry;
    this.entry = undefined;
    // 等待中的 open 完成后由 show 再关闭，避免提前 dispose 仍在挂载的内容。
    if (entry?.opened) {
      this.release(entry);
    }
  }

  reportError(error: MiniAppError): void {
    if (this.disposed) {
      return;
    }
    try {
      this.callbacks.onError(error);
    } catch (_) {
      SdkLogger.warn('LineDialog', 'errorCallbackFailed');
    }
    this.showError(error.code);
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.hide();
  }

  private async showError(code: string): Promise<void> {
    const generation = this.generation;
    try {
      const hostWindow = await window.getLastWindow(this.context);
      if (this.disposed || generation !== this.generation) {
        return;
      }
      const message: string = code === LineErrorCode.ACCOUNT_PROVIDER_REQUIRED ? '尚未配置 LINE 子窗口授权服务' :
        code === LineErrorCode.SUBWINDOW_CLOSE_FAILED ? '关闭上报失败，请稍后重试' : 'LINE 子窗口操作失败';
      hostWindow.getUIContext().getPromptAction().showToast({ message });
    } catch (_) {
      SdkLogger.warn('LineDialog', 'errorDisplayFailed');
    }
  }

  private async release(entry: LineDialogEntry): Promise<void> {
    if (entry.released) {
      return;
    }
    entry.released = true;
    try {
      await entry.uiContext.getPromptAction().closeCustomDialog(entry.content);
    } catch (_) {
      SdkLogger.warn('LineDialog', 'dialogCloseFailed');
    } finally {
      try {
        entry.content.dispose();
      } catch (_) {
        SdkLogger.warn('LineDialog', 'contentDisposeFailed');
      }
    }
  }
}
