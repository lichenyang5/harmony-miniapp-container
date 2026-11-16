import { HostLifecycleMonitor } from '../../../../core/HostLifecycleMonitor';
import { common } from '@kit.AbilityKit';
import { LinePhoneRegistrationSession } from '../LinePhoneRegistrationSession';
import { LinePhoneRegistrationState } from '../LineRegistrationSessionTypes';
import { LineRegistrationPresenter } from '../LineRegistrationUiTypes';
import { LineRegistrationWindow } from './LineRegistrationWindow';
import { LineRegistrationViewModel } from './LineRegistrationViewModel';
import { lineRegistrationBuilder, LineRegistrationViewParams } from './LineRegistrationView';

export class LineRegistrationDialogHost implements LineRegistrationPresenter {
  readonly context: common.UIAbilityContext;
  private readonly window: LineRegistrationWindow<LineRegistrationViewParams>;
  private readonly model: LineRegistrationViewModel = new LineRegistrationViewModel();
  constructor(context: common.UIAbilityContext) { this.context = context; this.window = new LineRegistrationWindow<LineRegistrationViewParams>(context); }
  assertCanPresent(): void { HostLifecycleMonitor.assertForeground(this.context); }
  show(session: LinePhoneRegistrationSession, back: () => void): Promise<void> {
    this.model.bind(session, this.context);
    return this.window.open(lineRegistrationBuilder, (hostWindow): LineRegistrationViewParams => ({ hostWindow, model: this.model, back }),
      back, (): boolean => this.model.dismissKeyboard?.() ?? false, (): void => { session.cancel(); this.hide(); });
  }
  update(state: LinePhoneRegistrationState): void { this.model.update(state); }
  async hide(): Promise<void> { this.model.dispose(); await this.window.hide(); }
}
