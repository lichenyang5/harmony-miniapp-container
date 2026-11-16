import { MiniAppError } from '../../../core/MiniAppError';
import { LineErrorCode } from '../LineErrorCode';

/** UI-independent identity: a visible idle form owns the account until its flow closes. */
export class LineAccountUiOwner { readonly identity: number = 0; }

export class LineAccountUiLease {
  private static readonly owners: WeakMap<Object, LineAccountUiOwner> = new WeakMap<Object, LineAccountUiOwner>();

  static acquire(account: Object): LineAccountUiOwner {
    LineAccountUiLease.assertRegistrationOwner(account);
    const owner = new LineAccountUiOwner();
    LineAccountUiLease.owners.set(account, owner);
    return owner;
  }

  static assertRegistrationOwner(account: Object, owner?: LineAccountUiOwner): void {
    const current = LineAccountUiLease.owners.get(account);
    if (current && current !== owner) {
      throw new MiniAppError(LineErrorCode.LOGIN_IN_PROGRESS, 'LINE account UI is in progress');
    }
  }

  static release(account: Object, owner: LineAccountUiOwner): void {
    if (LineAccountUiLease.owners.get(account) === owner) { LineAccountUiLease.owners.delete(account); }
  }
}
