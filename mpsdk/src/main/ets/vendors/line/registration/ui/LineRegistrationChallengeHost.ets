import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { LineRegistrationWindow } from './LineRegistrationWindow';
import { lineRegistrationWebBuilder, LineRegistrationWebViewParams } from './LineRegistrationWebView';
import { LineRegistrationWebProtocol, RegistrationWebKind, RegistrationWebResult } from './LineRegistrationWebProtocol';
import { MiniAppError } from '../../../../core/MiniAppError';
import { LineErrorCode } from '../../LineErrorCode';



/** Each instance owns exactly one WebView and its callback generation. */
export class LineRegistrationChallengeHost {
  private window?: LineRegistrationWindow<LineRegistrationWebViewParams>;
  private protocol?: LineRegistrationWebProtocol;
  private resolve?: (result: RegistrationWebResult) => void;
  private reject?: (error: MiniAppError) => void;
  private generation: number = 0;

  async show(context: common.UIAbilityContext, address: string, headers: webview.WebHeader[],
    kind: RegistrationWebKind): Promise<RegistrationWebResult> {
    this.cancel();
    const generation = ++this.generation;
    const protocol = new LineRegistrationWebProtocol(address, kind);
    this.protocol = protocol;
    const owned = new LineRegistrationWindow<LineRegistrationWebViewParams>(context);
    this.window = owned;
    const result = new Promise<RegistrationWebResult>((resolve, reject): void => { this.resolve = resolve; this.reject = reject; });
    result.catch((): void => {});
    try {
      await owned.open(lineRegistrationWebBuilder, (hostWindow): LineRegistrationWebViewParams => ({
        hostWindow, address, headers, kind, protocol,
        active: (): boolean => generation === this.generation && owned.isActive(),
        complete: (value: RegistrationWebResult): void => { if (generation === this.generation) { this.finish(value); } },
        fatal: (): void => {
          if (generation !== this.generation) { return; }
          const reject = this.reject;
          this.stop();
          reject?.(new MiniAppError(LineErrorCode.REGISTRATION_CANCELLED, 'LINE registration must restart'));
        }
      }), (): void => { if (generation === this.generation) { this.finish(RegistrationWebResult.CLOSED); } });
    } catch (_) {
      if (generation === this.generation) {
        const reject = this.reject; this.stop();
        reject?.(new MiniAppError(LineErrorCode.REGISTRATION_UNSUPPORTED, 'Unable to display LINE registration page'));
      }
    }
    return result;
  }

  cancel(): void { this.finish(RegistrationWebResult.CLOSED); }
  private finish(value: RegistrationWebResult): void { const resolve = this.resolve; this.stop(); resolve?.(value); }
  private stop(): void {
    this.generation++;
    this.resolve = undefined; this.reject = undefined;
    this.protocol?.stop(); this.protocol = undefined;
    const owned = this.window; this.window = undefined;
    owned?.hide();
  }
}
