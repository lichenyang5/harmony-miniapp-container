import { LineRegistrationDialogHost } from '../../registration/ui/LineRegistrationDialogHost';
import { LineRegistrationPresenter } from '../../registration/LineRegistrationUiTypes';
﻿import { MiniAppError } from '../../../../core/MiniAppError';
import { SdkLogger } from '../../../../logging/SdkLogger';
import { LineErrorCode } from '../../LineErrorCode';
import { common } from '@kit.AbilityKit';
import { ComponentContent, window } from '@kit.ArkUI';
import { LineLoginActions, LineLoginPresenter, LineLoginState } from '../LineLoginTypes';
import { lineLoginBuilder, LineLoginViewModel, LineLoginViewParams } from './LineLoginView';

class LoginEntry {
  opened: boolean = false;
  released: boolean = false;
  readonly uiContext: UIContext;
  readonly content: ComponentContent<LineLoginViewParams>;

  constructor(uiContext: UIContext, content: ComponentContent<LineLoginViewParams>) {
    this.uiContext = uiContext;
    this.content = content;
  }
}

export class LineLoginDialogHost implements LineLoginPresenter {
  readonly context: common.UIAbilityContext;
  private generation: number = 0;
  private entry?: LoginEntry;
  private model: LineLoginViewModel = new LineLoginViewModel();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async show(actions: LineLoginActions): Promise<void> {
    await this.hide();
    const generation: number = this.generation;
    let hostWindow: window.Window;
    try {
      hostWindow = await window.getLastWindow(this.context);
    } catch (error) {
      throw MiniAppError.from(error as Object, LineErrorCode.LOGIN_UI_FAILED, 'Unable to display LINE login');
    }
    if (generation !== this.generation) {
      return;
    }
    const uiContext: UIContext = hostWindow.getUIContext();
    const params: LineLoginViewParams = { hostWindow, model: this.model, actions };
    const content = new ComponentContent<LineLoginViewParams>(uiContext, lineLoginBuilder, params);
    const entry = new LoginEntry(uiContext, content);
    this.entry = entry;
    try {
      await uiContext.getPromptAction().openCustomDialog(content, {
        // 全屏外框不跟随键盘上移或压缩，输入区域在组件内独立避让。
        keyboardAvoidMode: KeyboardAvoidMode.NONE,
        autoCancel: false,
        isModal: true,
        alignment: DialogAlignment.Center,
        onWillDismiss: (action: DismissDialogAction): void => {
          if (this.entry === entry) {
            if (action.reason === DismissReason.PRESS_BACK && this.model.dismissKeyboard?.()) {
              return;
            }
            actions.cancel();
          } else {
            action.dismiss();
          }
        },
        onDidDisappear: (): void => {
          if (this.entry !== entry) {
            return;
          }
          this.entry = undefined;
          this.generation++;
          this.model.clearSecrets();
          this.release(entry).catch((): void => {
            SdkLogger.warn('LineLoginDialog', 'releaseFailed', { code: LineErrorCode.LOGIN_UI_FAILED });
          });
          actions.cancel();
        }
      });
      entry.opened = true;
      if (this.entry !== entry || generation !== this.generation) {
        await this.release(entry);
      }
    } catch (error) {
      if (this.entry === entry) {
        this.entry = undefined;
      }
      try {
        await this.release(entry);
      } catch (_) {
        SdkLogger.warn('LineLoginDialog', 'releaseFailed', { code: LineErrorCode.LOGIN_UI_FAILED });
      }
      throw MiniAppError.from(error as Object, LineErrorCode.LOGIN_UI_FAILED, 'Unable to display LINE login');
    }
  }

  registrationPresenter(): LineRegistrationPresenter { return new LineRegistrationDialogHost(this.context); }

  update(state: LineLoginState): void {
    this.model.update(state);
  }

  async hide(): Promise<void> {
    this.generation++;
    const entry = this.entry;
    this.entry = undefined;
    this.model.clearSecrets();
    if (entry?.opened) {
      await this.release(entry);
    }
  }

  private async release(entry: LoginEntry): Promise<void> {
    if (entry.released) {
      return;
    }
    entry.released = true;
    try {
      await entry.uiContext.getPromptAction().closeCustomDialog(entry.content);
    } catch (error) {
      throw new MiniAppError(LineErrorCode.LOGIN_UI_FAILED, 'Unable to close LINE login', error as Object);
    } finally {
      try {
        entry.content.dispose();
      } catch (_) {
        SdkLogger.warn('LineLoginDialog', 'disposeFailed', { code: LineErrorCode.LOGIN_UI_FAILED });
      }
    }
  }
}
