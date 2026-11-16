import { describe, expect, it } from '@ohos/hypium';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { VkPersonalCardHandler, VkPersonalCardParams } from '../main/ets/vendors/vk/handlers/VkPersonalCardHandler';
import { vkClientCode } from './VkErrorTestUtils';
import { EmptyParams, VkTestContext } from './TestContext';

export default function vkPersonalCardHandlerTest(): void {
  describe('VkPersonalCardHandler', () => {
    it('rejectsInvalidObjectBeforeOpeningSystemPicker', 0, async () => {
      const handler = new VkPersonalCardHandler(new VkTestContext());
      let code: string = '';
      try {
        await handler.getPersonalCard(JSON.parse('[]') as VkPersonalCardParams);
      } catch (error) {
        code = (error as MiniAppError).code;
      }
      expect(code).assertEqual('INVALID_ARGUMENT');
      handler.dispose();
    });

    it('rejectsMissingTypeBeforeOpeningSystemPicker', 0, async () => {
      const handler = new VkPersonalCardHandler(new VkTestContext());
      let code: string = '';
      try {
        await handler.getPersonalCard(new EmptyParams());
      } catch (error) {
        code = (error as MiniAppError).code;
      }
      expect(code).assertEqual('MISSING_REQUIRED_PARAMS');
      handler.dispose();
    });

    it('rejectsUnknownTypeElementBeforeOpeningSystemPicker', 0, async () => {
      const handler = new VkPersonalCardHandler(new VkTestContext());
      let code: string = '';
      try {
        await handler.getPersonalCard(JSON.parse('{"type":["sms"]}') as VkPersonalCardParams);
      } catch (error) {
        code = (error as MiniAppError).code;
      }
      expect(code).assertEqual('INVALID_ARGUMENT');
      handler.dispose();
    });

    it('rejectsEmptyTypeArrayBeforeOpeningSystemPicker', 0, async () => {
      const handler = new VkPersonalCardHandler(new VkTestContext());
      let code: string = '';
      try {
        await handler.getPersonalCard(JSON.parse('{"type":[]}') as VkPersonalCardParams);
      } catch (error) {
        code = (error as MiniAppError).code;
      }
      expect(code).assertEqual('INVALID_ARGUMENT');
      handler.dispose();
    });

    it('rejectsNonStringTypeElementBeforeOpeningSystemPicker', 0, async () => {
      const handler = new VkPersonalCardHandler(new VkTestContext());
      let code: string = '';
      try {
        await handler.getPersonalCard(JSON.parse('{"type":[1]}') as VkPersonalCardParams);
      } catch (error) {
        code = (error as MiniAppError).code;
      }
      expect(code).assertEqual('INVALID_ARGUMENT');
      handler.dispose();
    });

    it('rejectsAfterDisposeBeforeOpeningSystemPicker', 0, async () => {
      const handler = new VkPersonalCardHandler(new VkTestContext());
      handler.dispose();
      let code: string = '';
      try {
        await handler.getPersonalCard(JSON.parse('{"type":["phone"]}') as VkPersonalCardParams);
      } catch (error) {
        code = vkClientCode(error as Object);
      }
      expect(code).assertEqual('1');
    });
  });
}
