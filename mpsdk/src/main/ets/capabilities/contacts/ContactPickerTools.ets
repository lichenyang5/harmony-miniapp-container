import { common } from '@kit.AbilityKit';
import { contact } from '@kit.ContactsKit';
import { assertHostForeground } from '../../core/HostLifecycleMonitor';
import { MiniAppError } from '../../core/MiniAppError';
import {
  CAPABILITY_BUSY,
  INVALID_CAPABILITY_RESULT,
  NOT_SUPPORTED,
  SESSION_CLOSED,
  SYSTEM_ERROR,
  USER_CANCELLED
} from '../../core/MiniAppErrorCode';
import { ParamAssert } from '../../utils/ParamAssert';

/** 系统选择器由原生调用控制；会话释放只阻止交付，原生调用结束才释放占用。 */
export class ContactPickerTools {
  private static readonly activeContexts: Set<common.UIAbilityContext> = new Set<common.UIAbilityContext>();
  private readonly context: common.UIAbilityContext;
  private disposed: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async pick(): Promise<contact.Contact> {
    this.assertOpen();
    if (!canIUse('SystemCapability.Applications.Contacts')) {
      throw new MiniAppError(NOT_SUPPORTED, 'Contact picker is not supported');
    }
    assertHostForeground(this.context);
    if (ContactPickerTools.activeContexts.has(this.context)) {
      throw new MiniAppError(CAPABILITY_BUSY, 'Contact picker is already open');
    }
    ContactPickerTools.activeContexts.add(this.context);
    try {
      const options: contact.ContactSelectionOptions = {
        isMultiSelect: false, maxSelectable: 1, isDisplayedByName: false
      };
      let selected: Array<contact.Contact>;
      try {
        selected = await contact.selectContacts(options);
      } catch (error) {
        this.assertOpen();
        throw new MiniAppError(SYSTEM_ERROR, 'Contact picker failed', error as Object);
      }
      this.assertOpen();
      if (!Array.isArray(selected)) {
        throw new MiniAppError(INVALID_CAPABILITY_RESULT, 'Contact picker returned an invalid result');
      }
      if (selected.length === 0) {
        throw new MiniAppError(USER_CANCELLED, 'No contact selected');
      }
      const first = selected[0];
      try {
        ParamAssert.assertObject(first, 'contact');
      } catch (error) {
        throw new MiniAppError(INVALID_CAPABILITY_RESULT, 'Contact picker returned an invalid contact',
          error as Object);
      }
      return first;
    } finally {
      ContactPickerTools.activeContexts.delete(this.context);
    }
  }

  dispose(): void {
    this.disposed = true;
  }

  private assertOpen(): void {
    if (this.disposed) {
      throw new MiniAppError(SESSION_CLOSED, 'Contact picker is closed');
    }
  }
}
