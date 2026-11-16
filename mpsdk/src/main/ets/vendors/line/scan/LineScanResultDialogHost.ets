import { common } from '@kit.AbilityKit';
import { ComponentContent, window } from '@kit.ArkUI';
import { MiniAppError } from '../../../core/MiniAppError';
import { SdkLogger } from '../../../logging/SdkLogger';
import { LineErrorCode } from '../LineErrorCode';
import { lineScanResultBuilder } from './LineScanResultView';
import { LineScanResultAction, LineScanResultViewParams } from './LineScanResultTypes';

class ScanResultEntry {
  cancelled: boolean = false;
  opened: boolean = false;
  opening?: Promise<void>;
  releasing?: Promise<void>;
  uiContext?: UIContext;
  content?: ComponentContent<LineScanResultViewParams>;
  params?: LineScanResultViewParams;
  readonly result: Promise<LineScanResultAction>;
  resolve: (action: LineScanResultAction) => void = (_action: LineScanResultAction): void => {};

  constructor() {
    this.result = new Promise<LineScanResultAction>((resolve): void => { this.resolve = resolve; });
  }
}

/** 单次结果弹层归当前扫码所有，先释放弹层再交付操作，不持久化扫描内容。 */
export class LineScanResultDialogHost {
  private readonly context: common.UIAbilityContext;
  private entry?: ScanResultEntry;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async show(value: string, isLink: boolean, isCurrent: () => boolean): Promise<LineScanResultAction> {
    this.dismiss();
    const entry = new ScanResultEntry();
    this.entry = entry;
    try {
      const hostWindow = await window.getLastWindow(this.context);
      // 获取窗口期间来源可能已退到后台；挂载前重新确认，不能只依赖扫码返回时的检查。
      if (entry.cancelled || !isCurrent()) {
        await this.finish(entry, LineScanResultAction.CLOSE);
        return LineScanResultAction.CLOSE;
      }
      const uiContext = hostWindow.getUIContext();
      entry.uiContext = uiContext;
      const params: LineScanResultViewParams = {
        value, isLink, complete: (action: LineScanResultAction): void => {
          this.finish(entry, isCurrent() ? action : LineScanResultAction.CLOSE);
        }
      };
      entry.params = params;
      entry.content = new ComponentContent<LineScanResultViewParams>(uiContext, lineScanResultBuilder, params);
      entry.opening = uiContext.getPromptAction().openCustomDialog(entry.content, {
        autoCancel: true, isModal: true, alignment: DialogAlignment.Center,
        onWillDismiss: (action: DismissDialogAction): void => {
          if (entry.cancelled) {
            action.dismiss();
          } else {
            this.finish(entry, LineScanResultAction.CLOSE);
          }
        },
        onDidDisappear: (): void => { this.finish(entry, LineScanResultAction.CLOSE); }
      }).then((): void => { entry.opened = true; });
      await entry.opening;
      return await entry.result;
    } catch (error) {
      await this.finish(entry, LineScanResultAction.CLOSE);
      throw MiniAppError.from(error as Object, LineErrorCode.QR_READER_FAILED, 'Unable to display scan result');
    }
  }

  dismiss(): void {
    if (this.entry) {
      this.finish(this.entry, LineScanResultAction.CLOSE);
    }
  }

  private finish(entry: ScanResultEntry, action: LineScanResultAction): Promise<void> {
    if (entry.releasing) {
      return entry.releasing;
    }
    entry.cancelled = true;
    if (this.entry === entry) {
      this.entry = undefined;
    }
    entry.releasing = this.release(entry, action);
    return entry.releasing;
  }

  private async release(entry: ScanResultEntry, action: LineScanResultAction): Promise<void> {
    let resultAction: LineScanResultAction = action;
    try {
      // 平台完成挂载后才能 close/dispose，避免扫码期间来源销毁导致迟到弹层。
      await entry.opening;
      if (entry.opened && entry.content && entry.uiContext) {
        await entry.uiContext.getPromptAction().closeCustomDialog(entry.content);
      }
    } catch (_) {
      resultAction = LineScanResultAction.CLOSE;
      SdkLogger.warn('LineScanResult', 'releaseFailed', { code: LineErrorCode.QR_READER_FAILED });
    } finally {
      try {
        entry.content?.dispose();
      } catch (_) { /* 单个内容释放失败仍需清除扫描内容并结束等待。 */
      }
      if (entry.params) {
        entry.params.value = '';
      }
      entry.content = undefined;
      entry.params = undefined;
      entry.uiContext = undefined;
      entry.resolve(resultAction);
    }
  }
}
