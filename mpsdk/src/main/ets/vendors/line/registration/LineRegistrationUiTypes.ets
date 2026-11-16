import { common } from '@kit.AbilityKit';
import { LinePhoneRegistrationSession } from './LinePhoneRegistrationSession';
import { LinePhoneRegistrationState } from './LineRegistrationSessionTypes';

export interface LineRegistrationRequest {
  result: Promise<void>;
  cancel: () => void;
}

/** Internal presentation contract, scoped to one account coordinator flow. */
export interface LineRegistrationPresenter {
  readonly context: common.UIAbilityContext;
  assertCanPresent?(): void;
  show(session: LinePhoneRegistrationSession, back: () => void): Promise<void>;
  update(state: LinePhoneRegistrationState): void;
  hide(): Promise<void>;
}
