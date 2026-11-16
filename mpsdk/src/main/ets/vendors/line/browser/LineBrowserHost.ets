import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { WebNewWindow } from '../../../web/WebNewWindowRequest';
import { ComponentContent, window } from '@kit.ArkUI';
import { MiniAppError } from '../../../core/MiniAppError';
import { MiniAppInfo, MiniAppOpenHandler } from '../../../core/MiniAppOptions';
import { DOCUMENT_CHANGED, NOT_SUPPORTED, SESSION_CLOSED } from '../../../core/MiniAppErrorCode';
import { SdkLogger } from '../../../logging/SdkLogger';
import { LineConsentDialogHost } from '../consent/ui/LineConsentDialogHost';
import { LineErrorCode } from '../LineErrorCode';
import { lineBrowserBuilder, LineBrowserViewParams } from './LineBrowserView';
import { validateLineBrowserUrl } from './LineBrowserUrl';
import { MiniAppLifecycle } from '../../../core/lifecycle/MiniAppLifecycle';
import { LineAdapter } from '../LineAdapter';
import { LineMode } from '../LineMode';

class LineBrowserEntry {
  openingMiniApp: boolean = false;
  cancelled: boolean = false;
  opened: boolean = false;
  started: boolean = false;
  opening?: Promise<void>;
  releasing?: Promise<void>;
  uiContext?: UIContext;
  content?: ComponentContent<LineBrowserViewParams>;
}

/** 由创建者管理生命周期；只承载普通网页，不创建小程序 Session 或读取账号。 */
export class LineBrowserHost {
  private readonly context: common.UIAbilityContext;
  private readonly entries: Set<LineBrowserEntry> = new Set<LineBrowserEntry>();
  private disposed: boolean = false;
  private readonly openMiniApp?: MiniAppOpenHandler;
  private readonly adapter?: LineAdapter;
  private readonly lifecycle?: MiniAppLifecycle;

  /** 帮助等纯浏览场景可不提供小程序宿主跳转，也不继承原生账号授权。 */
  constructor(context: common.UIAbilityContext, openMiniApp?: MiniAppOpenHandler,
    adapter?: LineAdapter, lifecycle?: MiniAppLifecycle) {
    this.context = context;
    this.openMiniApp = openMiniApp;
    this.adapter = adapter;
    this.lifecycle = lifecycle;
  }

  async open(address: string): Promise<void> {
    validateLineBrowserUrl(address);
    const entry = this.createEntry();
    await this.showEntry(entry, address);
  }

  /** 地址可能稍后由 opener 设置，控制器必须先同步交给内核。 */
  reserveWindow(address: string): WebNewWindow {
    if (address !== '' && address !== 'about:blank') validateLineBrowserUrl(address);
    const controller = new webview.WebviewController();
    const entry = this.createEntry();
    const popup: WebNewWindow = {
      controller,
      show: (): Promise<void> => this.showEntry(entry, address, controller),
      close: (): void => { this.release(entry); }
    };
    return popup;
  }

  private createEntry(): LineBrowserEntry {
    if (this.disposed) {
      throw new MiniAppError(SESSION_CLOSED, 'LINE browser host is closed');
    }
    const entry = new LineBrowserEntry();
    this.entries.add(entry);
    return entry;
  }

  private async showEntry(entry: LineBrowserEntry, address: string,
    popupController?: webview.WebviewController): Promise<void> {
    this.ensureActive(entry);
    if (entry.started) throw new MiniAppError(LineErrorCode.BROWSER_FAILED, 'Browser is already being shown');
    entry.started = true;
    try {
      const hostWindow = await window.getLastWindow(this.context);
      this.ensureActive(entry);
      const uiContext: UIContext = hostWindow.getUIContext();
      const params: LineBrowserViewParams = {
        hostWindow, url: address, isAvailable: (): boolean => !this.disposed && !entry.cancelled, close: (): void => {
          this.release(entry);
        },
        openMiniApp: async (app: MiniAppInfo): Promise<void> => {
          this.ensureActive(entry);
          if (!this.openMiniApp) {
            throw new MiniAppError(NOT_SUPPORTED, 'Mini app opening is unavailable in this browser');
          }
          if (entry.openingMiniApp) {
            throw new MiniAppError(LineErrorCode.BROWSER_FAILED, 'Mini app opening is already in progress');
          }
          entry.openingMiniApp = true;
          try {
            await this.openMiniApp(app);
            await this.release(entry);
          } catch (error) {
            const failure = MiniAppError.from(error as Object, LineErrorCode.BROWSER_FAILED, 'Unable to open mini app');
            // 同一小程序内跳转可能已完成，但所属会话会以 DOCUMENT_CHANGED 丢弃原文档的完成结果。
            // 来源失效时只释放浏览器，不吞掉或伪造宿主结果。
            if (failure.code === DOCUMENT_CHANGED || failure.code === SESSION_CLOSED) {
              await this.release(entry);
            }
            throw failure;
          } finally {
            entry.openingMiniApp = false;
          }
        }
      };
      if (popupController) params.popupController = popupController;
      if (this.adapter?.mode === LineMode.CLIENT) {
        if (!this.lifecycle) {
          throw new MiniAppError(LineErrorCode.BROWSER_FAILED, 'LINE browser owner lifecycle is unavailable');
        }
        params.nativeAuth = {
          adapter: this.adapter, lifecycle: this.lifecycle, consent: new LineConsentDialogHost(this.context)
        };
      }
      entry.uiContext = uiContext;
      entry.content = new ComponentContent<LineBrowserViewParams>(uiContext, lineBrowserBuilder, params);
      entry.opening = uiContext.getPromptAction().openCustomDialog(entry.content, {
        keyboardAvoidMode: KeyboardAvoidMode.NONE,
        autoCancel: false,
        isModal: true,
        alignment: DialogAlignment.Center,
        onWillDismiss: (action: DismissDialogAction): void => {
          if (entry.cancelled) {
            action.dismiss();
          } else if (params.back?.()) {
            return;
          } else {
            this.release(entry);
          }
        },
        onDidDisappear: (): void => {
          this.release(entry);
        }
      }).then((): void => {
        entry.opened = true;
      });
      await entry.opening;
      this.ensureActive(entry);
    } catch (error) {
      await this.release(entry);
      throw MiniAppError.from(error as Object, LineErrorCode.BROWSER_FAILED, 'Unable to show LINE browser');
    }
  }

  /** 页面切换关闭所属窗口；宿主仍可服务下一份文档。 */
  dismissAll(): void {
    Array.from(this.entries).forEach((entry: LineBrowserEntry): void => {
      this.release(entry);
    });
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.dismissAll();
  }

  private ensureActive(entry: LineBrowserEntry): void {
    if (this.disposed || entry.cancelled) {
      throw new MiniAppError(this.disposed ? SESSION_CLOSED : DOCUMENT_CHANGED, 'LINE browser opening cancelled');
    }
  }

  private release(entry: LineBrowserEntry): Promise<void> {
    if (entry.releasing) {
      return entry.releasing;
    }
    entry.cancelled = true;
    this.entries.delete(entry);
    entry.releasing = this.releaseContent(entry);
    return entry.releasing;
  }

  private async releaseContent(entry: LineBrowserEntry): Promise<void> {
    try {
      // 挂载完成前不可 close/dispose；只等待平台打开操作，不等待网页加载。
      await entry.opening;
      if (entry.opened && entry.content && entry.uiContext) {
        await entry.uiContext.getPromptAction().closeCustomDialog(entry.content);
      }
    } catch (_) {
      SdkLogger.warn('LineBrowser', 'dialogReleaseFailed', { code: LineErrorCode.BROWSER_FAILED });
    } finally {
      try {
        entry.content?.dispose();
      } catch (_) {
        SdkLogger.warn('LineBrowser', 'contentDisposeFailed', { code: LineErrorCode.BROWSER_FAILED });
      }
      entry.content = undefined;
      entry.uiContext = undefined;
    }
  }
}
