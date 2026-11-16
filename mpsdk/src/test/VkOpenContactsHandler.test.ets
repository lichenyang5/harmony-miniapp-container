import { describe, expect, it } from '@ohos/hypium';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { VkAdapter } from '../main/ets/vendors/vk/VkAdapter';
import { VkUsersHandler } from '../main/ets/vendors/vk/handlers/VkUsersHandler';
import { vkClientCode } from './VkErrorTestUtils';
import { EmptyParams, VkTestContext } from './TestContext';

export default function vkOpenContactsHandlerTest(): void {
  describe('VkOpenContactsHandler', () => {
    it('rejectsInvalidObjectBeforeOpeningSystemPicker', 0, async () => {
      const handler = new VkUsersHandler(new VkTestContext(), new VkAdapter());
      let code: string = '';
      try {
        await handler.openContacts(JSON.parse('[]') as object);
      } catch (error) {
        code = (error as MiniAppError).code;
      }
      expect(code).assertEqual('INVALID_ARGUMENT');
      handler.dispose();
    });

    it('rejectsAfterDisposeBeforeOpeningSystemPicker', 0, async () => {
      const handler = new VkUsersHandler(new VkTestContext(), new VkAdapter());
      handler.dispose();
      let code: string = '';
      try {
        await handler.openContacts(new EmptyParams());
      } catch (error) {
        code = vkClientCode(error as Object);
      }
      expect(code).assertEqual('1');
    });
  });
}
