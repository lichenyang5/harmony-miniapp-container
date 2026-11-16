import { LineRegistrationPresenter } from '../registration/LineRegistrationUiTypes';
import { common } from '@kit.AbilityKit';

export type LineLoginPhase = 'loading' | 'qr' | 'email' | 'confirming' | 'pin' | 'failed' | 'expired';

export interface LineLoginState {
  phase: LineLoginPhase;
  method: 'qr' | 'email';
  qrUrl?: string;
  pin?: string;
  remainingSeconds?: number;
  errorCode?: string;
}

export interface LineLoginActions {
  showQr(): void;

  showEmail(): void;

  submitEmail(email: string, password: string): void;

  retry(): void;

  register?(): void;

  cancel(): void;
}

export interface LineLoginPresenter {
  readonly context: common.UIAbilityContext;

  show(actions: LineLoginActions): Promise<void>;

  update(state: LineLoginState): void;

  hide(): Promise<void>;

  registrationPresenter?(): LineRegistrationPresenter;
}

export interface LineLoginRequest {
  result: Promise<void>;
  cancel: () => void;
}
