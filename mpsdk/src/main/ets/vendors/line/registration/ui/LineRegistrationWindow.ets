import { MiniAppError } from '../../../../core/MiniAppError';
import { LineErrorCode } from '../../LineErrorCode';
import { common } from '@kit.AbilityKit';
import { ComponentContent, window } from '@kit.ArkUI';
import { HostLifecycleMonitor, HostLifecycleObserver } from '../../../../core/HostLifecycleMonitor';

class RegistrationEntry<T extends Object> {
  opened: boolean = false;
  released: boolean = false;
  readonly ui: UIContext;
  readonly content: ComponentContent<T>;
  constructor(ui: UIContext, content: ComponentContent<T>) { this.ui = ui; this.content = content; }
}

/** Internal full-screen window lifetime shared only by registration form/web windows. */
export class LineRegistrationWindow<T extends Object> implements HostLifecycleObserver {
  private entry?: RegistrationEntry<T>;
  private generation: number = 0;
  private unsubscribe?: () => void;
  private active: boolean = false;
  private foreground: boolean = false;
  readonly context: common.UIAbilityContext;
  private onOwnerDestroyed?: () => void;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  onForegroundChanged(foreground: boolean): void { this.foreground = foreground; }
  onDestroyed(): void { const callback = this.onOwnerDestroyed; this.hide(); callback?.(); }

  isActive(): boolean { return this.active && this.foreground; }

  async open(builder: WrappedBuilder<[T]>, params: (host: window.Window) => T,
    cancel: () => void, dismissKeyboard?: () => boolean, destroyed?: () => void): Promise<void> {
    HostLifecycleMonitor.assertForeground(this.context);
    this.hide();
    const generation = ++this.generation;
    this.active = true;
    this.onOwnerDestroyed = destroyed ?? cancel;
    const unsubscribe = HostLifecycleMonitor.observe(this.context, this);
    if (!this.active || generation !== this.generation) { unsubscribe(); return; }
    this.unsubscribe = unsubscribe;
    let created: RegistrationEntry<T> | undefined;
    try {
      const host = await window.getLastWindow(this.context);
      if (!this.active || generation !== this.generation) { return; }
      if (!this.foreground) { await this.hide(); cancel(); return; }
      HostLifecycleMonitor.assertForeground(this.context);
      const ui = host.getUIContext();
      const content = new ComponentContent<T>(ui, builder, params(host));
      const entry = new RegistrationEntry<T>(ui, content);
      created = entry;
      this.entry = entry;
      await ui.getPromptAction().openCustomDialog(content, {
        keyboardAvoidMode: KeyboardAvoidMode.NONE, autoCancel: false, isModal: true, alignment: DialogAlignment.Center,
        onWillDismiss: (action: DismissDialogAction): void => {
          if (this.entry !== entry) { action.dismiss(); return; }
          if (action.reason === DismissReason.PRESS_BACK && dismissKeyboard?.()) { return; }
          cancel();
        },
        onDidDisappear: (): void => {
          if (this.entry === entry) { this.hide(); cancel(); }
        }
      });
      entry.opened = true;
      if (!this.active || generation !== this.generation || this.entry !== entry) { await this.release(entry); }
    } catch (error) {
      // A cancelled opening may reject after a replacement has taken ownership.
      // Keep the local entry; never use the replacement entry for old cleanup.
      if (generation === this.generation) { await this.hide(); }
      if (created) { await this.release(created); }
      throw new MiniAppError(LineErrorCode.LOGIN_UI_FAILED, 'Unable to display LINE registration');
    }
  }

  async hide(): Promise<void> {
    this.active = false;
    this.foreground = false;
    this.generation++;
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.onOwnerDestroyed = undefined;
    const entry = this.entry;
    this.entry = undefined;
    if (entry?.opened) { await this.release(entry); }
  }

  private async release(entry: RegistrationEntry<T>): Promise<void> {
    if (entry.released) { return; }
    entry.released = true;
    try { await entry.ui.getPromptAction().closeCustomDialog(entry.content); }
    catch (_) { /* Disposal must still run after owner destruction. */ }
    finally { try { entry.content.dispose(); } catch (_) { /* Already disposed. */ } }
  }
}
