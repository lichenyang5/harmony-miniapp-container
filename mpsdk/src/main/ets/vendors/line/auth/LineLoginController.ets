import { LineAccountManager } from './LineAccountManager';
import { LineQrLoginState } from './LineAccountTypes';
import { LineEmailLoginState } from './LineEmailLoginTypes';
import { LineLoginActions, LineLoginState } from './LineLoginTypes';
import { LineErrorCode } from '../LineErrorCode';
import { MiniAppError } from '../../../core/MiniAppError';

/** Refresh-button wait only; this is not the QR code or login session lifetime. */
const QR_REFRESH_WAIT_MS: number = 30000;

/** One deferred result spans explicit retries and method switches. */
export class LineLoginController implements LineLoginActions {
  private readonly onRegister?: () => void;
  private readonly account: LineAccountManager;
  private readonly onChange: (state: LineLoginState) => void;
  private result?: Promise<string>;
  private resolveResult?: (mid: string) => void;
  private rejectResult?: (error: MiniAppError) => void;
  private active: boolean = true;
  private generation: number = 0;
  private loginVersion?: number;
  private method: 'qr' | 'email' = 'qr';
  private busy: boolean = false;
  private timer: number = -1;
  private restoreError?: MiniAppError;

  constructor(account: LineAccountManager, onChange: (state: LineLoginState) => void, onRegister?: () => void) {
    this.onRegister = onRegister;
    this.account = account;
    this.onChange = onChange;
  }

  start(initialRestoreError?: MiniAppError): Promise<string> {
    if (!this.result) {
      this.result = new Promise<string>((resolve, reject): void => {
        this.resolveResult = resolve;
        this.rejectResult = reject;
      });
      if (this.active && initialRestoreError) {
        this.restoreError = initialRestoreError;
        this.publish({ phase: 'failed', method: 'qr', errorCode: initialRestoreError.code });
      } else if (this.active) {
        this.showQr();
      } else {
        this.rejectResult?.(
          new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE login cancelled'));
      }
    }
    return this.result;
  }

  showQr(): void {
    if (!this.active) {
      return;
    }
    this.resetAttempt();
    this.restoreError = undefined;
    this.method = 'qr';
    this.run();
  }

  showEmail(): void {
    if (!this.active) {
      return;
    }
    this.resetAttempt();
    this.restoreError = undefined;
    this.method = 'email';
    this.publish({ phase: 'email', method: 'email' });
  }

  submitEmail(email: string, password: string): void {
    if (!this.active || this.method !== 'email' || this.busy) {
      return;
    }
    this.resetAttempt();
    this.run(email, password);
    email = '';
    password = '';
  }

  retry(): void {
    if (!this.active || this.busy) {
      return;
    }
    if (this.restoreError) {
      this.retryRestore();
      return;
    }
    if (this.method === 'email') {
      this.showEmail();
    } else {
      this.showQr();
    }
  }

  cancel(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.resetAttempt();
    this.rejectResult?.(new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE login cancelled'));
  }

  register(): void {
    if (this.active) { this.onRegister?.(); }
  }

  dispose(): void {
    this.cancel();
  }

  private async retryRestore(): Promise<void> {
    this.resetAttempt();
    const generation: number = this.generation;
    this.busy = true;
    this.publish({ phase: 'loading', method: 'qr' });
    if (!this.current(generation)) {
      return;
    }
    try {
      const restored: boolean = await this.account.restoreSession();
      if (!this.current(generation)) {
        return;
      }
      if (!restored) {
        this.showQr();
        return;
      }
      const mid: string | undefined = this.account.getAccountId();
      if (!mid) {
        throw new MiniAppError(LineErrorCode.LOGIN_REQUIRED, 'LINE account is unavailable');
      }
      this.active = false;
      this.restoreError = undefined;
      this.resolveResult?.(mid);
    } catch (error) {
      if (!this.current(generation)) {
        return;
      }
      const failure: MiniAppError = MiniAppError.from(error as Object,
        LineErrorCode.ACCOUNT_RESTORE_FAILED, 'LINE account restore failed');
      this.restoreError = failure;
      this.publish({ phase: 'failed', method: 'qr', errorCode: failure.code });
    } finally {
      if (generation === this.generation) {
        this.busy = false;
      }
    }
  }

  private resetAttempt(): void {
    this.generation++;
    this.clearTimer();
    const version: number | undefined = this.loginVersion;
    this.loginVersion = undefined;
    this.busy = false;
    if (version !== undefined) {
      this.account.cancelLogin(version);
    }
  }

  private current(generation: number): boolean {
    return this.active && this.generation === generation;
  }

  private started(version: number, generation: number): void {
    if (!this.current(generation)) {
      this.account.cancelLogin(version);
    } else {
      this.loginVersion = version;
    }
  }

  private async run(email: string = '', password: string = ''): Promise<void> {
    const generation: number = this.generation;
    const method: 'qr' | 'email' = this.method;
    this.busy = true;
    this.publish({ phase: 'loading', method });
    if (!this.current(generation)) {
      return;
    }
    try {
      const pending: Promise<string> = method === 'qr' ? this.account.startQrLogin(
        (state: LineQrLoginState): void => this.qrState(state, generation),
        (version: number): void => this.started(version, generation)) : this.account.startEmailLogin(email, password,
        (state: LineEmailLoginState): void => {
          if (!this.current(generation)) {
            return;
          }
          if (state.kind === 'pinReady') {
            this.publish({ phase: 'pin', method, pin: state.pin });
          } else if (state.kind ===
            'waitingForConfirmation') {
            this.publish({ phase: 'confirming', method });
          }
        }, (version: number): void => this.started(version, generation));
      email = '';
      password = '';
      const mid: string = await pending;
      if (!this.current(generation)) {
        return;
      }
      this.active = false;
      this.clearTimer();
      this.resolveResult?.(mid);
    } catch (error) {
      if (!this.current(generation)) {
        return;
      }
      this.clearTimer();
      const code: string = error instanceof MiniAppError ? error.code :
        (method === 'qr' ? LineErrorCode.LOGIN_FAILED : LineErrorCode.EMAIL_LOGIN_FAILED);
      this.publish(
        { phase: code === LineErrorCode.QR_CONFIRM_TIMEOUT ? 'expired' : 'failed', method, errorCode: code });
    } finally {
      email = '';
      password = '';
      if (generation === this.generation) {
        this.loginVersion = undefined;
        this.busy = false;
      }
    }
  }

  private qrState(state: LineQrLoginState, generation: number): void {
    if (!this.current(generation)) {
      return;
    }
    if (state.kind === 'qrReady') {
      this.clearTimer();
      const readyAt: number = Date.now() + QR_REFRESH_WAIT_MS;
      const update = (): void => {
        if (!this.current(generation)) {
          return;
        }
        const remainingSeconds: number = Math.max(0, Math.ceil((readyAt - Date.now()) / 1000));
        if (remainingSeconds === 0) {
          this.clearTimer();
        }
        this.publish({
          phase: 'qr',
          method: 'qr',
          qrUrl: state.url,
          remainingSeconds
        });
      };
      update();
      if (this.current(generation)) {
        this.timer = setInterval(update, 1000);
      }
    } else if (state.kind === 'qrVerified' || state.kind === 'pinReady') {
      this.clearTimer();
      this.publish({ phase: state.kind === 'pinReady' ? 'pin' : 'confirming', method: 'qr', pin: state.pin });
    }
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
    }
    this.timer = -1;
  }

  private publish(state: LineLoginState): void {
    try {
      this.onChange(state);
    } catch (_) { /* UI observers cannot change authentication. */
    }
  }
}
