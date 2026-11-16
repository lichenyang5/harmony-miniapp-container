import { describe, expect, it } from '@ohos/hypium';
import { ContactPickerTools } from '../main/ets/capabilities/contacts/ContactPickerTools';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { SESSION_CLOSED } from '../main/ets/core/MiniAppErrorCode';
import { getTestUiAbilityContext } from './TestContext';

export default function contactPickerToolsTest(): void {
  describe('ContactPickerTools', () => {
    it('rejectsUseAfterDisposeBeforeOpeningSystemPicker', 0, async () => {
      const picker = new ContactPickerTools(getTestUiAbilityContext());
      picker.dispose();
      picker.dispose();
      let code: string = '';
      try {
        await picker.pick();
      } catch (error) {
        code = (error as MiniAppError).code;
      }
      expect(code).assertEqual(SESSION_CLOSED);
    });
  });
}
