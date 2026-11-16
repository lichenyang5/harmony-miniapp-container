import { common } from '@kit.AbilityKit';
import { ComponentContent, window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { MiniAppError } from '../../../../core/MiniAppError';
import { LineErrorCode } from '../../LineErrorCode';
import { LineConsentPage, LineConsentPresenter, LineConsentRequest } from '../LineConsentTypes';
import { LineConsentProtocol } from '../LineConsentProtocol';
import { lineConsentBuilder, LineConsentViewParams } from './LineConsentView';
import { LineBrowserHost } from '../../browser/LineBrowserHost';

class ConsentEntry {
  readonly result: Promise<boolean>;
  finished: boolean = false;
  opened: boolean = false;
  opening?: Promise<void>;
  uiContext?: UIContext;
  content?: ComponentContent<LineConsentViewParams>;
  params?: LineConsentViewParams;

  constructor() {
    this.result = new Promise<boolean>((resolve, reject): void => {
      this.resolve = resolve;
      this.reject = reject;
    });
  }

  resolve: (allowed: boolean) => void = (_allowed: boolean): void => {
  };

  reject: (error: MiniAppError) => void = (_error: MiniAppError): void => {
  };
}

/** 复用 LINE 登录弹层的 ComponentContent 承载方式，资源仅归当前授权请求所有。 */
export class LineConsentDialogHost implements LineConsentPresenter {
  private readonly context: common.UIAbilityContext;
  private entry?: ConsentEntry;
  private readonly browser: LineBrowserHost;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.browser = new LineBrowserHost(context);
  }

  request(page: LineConsentPage): LineConsentRequest {
    if (this.entry) {
      throw new MiniAppError(LineErrorCode.CONSENT_BUSY, 'LINE 授权正在进行');
    }
    const address: string = LineConsentProtocol.validateUrl(page.url);
    const entry: ConsentEntry = new ConsentEntry();
    this.entry = entry;
    this.open(entry, address, page.headers).catch((error: Object): void => {
      this.finish(entry, MiniAppError.from(error, LineErrorCode.CONSENT_UI_FAILED, '无法展示 LINE 授权页面'));
    });
    return {
      result: entry.result, cancel: (): void => {
        this.finish(entry, new MiniAppError(LineErrorCode.CONSENT_CANCELLED, 'LINE 授权已取消'));
      }
    };
  }

  private async open(entry: ConsentEntry, address: string, headers: Record<string, string>): Promise<void> {
    const hostWindow = await window.getLastWindow(this.context);
    if (entry.finished) {
      return;
    }
    const uiContext: UIContext = hostWindow.getUIContext();
    const params: LineConsentViewParams = {
      hostWindow,
      url: address,
      headers: Object.keys(headers)
        .map((key: string): webview.WebHeader => ({ headerKey: key, headerValue: headers[key] })),
      openBrowser: async (target: string): Promise<void> => {
        if (entry.finished) {
          throw new MiniAppError(LineErrorCode.CONSENT_CANCELLED, 'LINE consent is no longer active');
        }
        await this.browser.open(target);
      },
      complete: (allowed: boolean): void => {
        this.finish(entry, undefined, allowed);
      },
      fail: (): void => {
        this.finish(entry, new MiniAppError(LineErrorCode.CONSENT_UI_FAILED, 'LINE 授权页面加载失败'));
      }
    };
    entry.params = params;
    entry.uiContext = uiContext;
    entry.content = new ComponentContent<LineConsentViewParams>(uiContext, lineConsentBuilder, params);
    entry.opening = uiContext.getPromptAction().openCustomDialog(entry.content, {
      keyboardAvoidMode: KeyboardAvoidMode.NONE,
      autoCancel: false,
      isModal: true,
      alignment: DialogAlignment.Center,
      onWillDismiss: (action: DismissDialogAction): void => {
        if (entry.finished) {
          action.dismiss();
        } else {
          params.complete(false);
        }
      },
      onDidDisappear: (): void => {
        params.complete(false);
      }
    }).then((): void => {
      entry.opened = true;
    });
    await entry.opening;
  }

  private async finish(entry: ConsentEntry, failure?: MiniAppError, allowed: boolean = false): Promise<void> {
    if (entry.finished) {
      return;
    }
    entry.finished = true;
    this.browser.dismissAll();
    try {
      // 取消发生在 open 完成前时，等待其挂载完成再释放，避免 Invalid input parameter。
      await entry.opening;
      if (entry.opened && entry.content && entry.uiContext) {
        await entry.uiContext.getPromptAction().closeCustomDialog(entry.content);
      }
    } catch (error) {
      if (!failure) {
        failure =
          MiniAppError.from(error as Object, LineErrorCode.CONSENT_UI_FAILED, '无法关闭 LINE 授权页面');
      }
    } finally {
      try {
        entry.content?.dispose();
      } catch (error) {
        if (!failure) {
          failure =
            MiniAppError.from(error as Object, LineErrorCode.CONSENT_UI_FAILED, '无法释放 LINE 授权页面');
        }
      }
      if (entry.params) {
        entry.params.headers = [];
      }
      if (this.entry === entry) {
        this.entry = undefined;
      }
      if (failure) {
        entry.reject(failure);
      } else {
        entry.resolve(allowed);
      }
    }
  }
}
