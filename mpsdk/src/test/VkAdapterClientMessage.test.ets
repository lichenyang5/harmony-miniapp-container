import { vkClientCode } from './VkErrorTestUtils';
import { describe, expect, it } from '@ohos/hypium';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { VkAdapter } from '../main/ets/vendors/vk/VkAdapter';

export default function vkAdapterClientMessageTest(): void {
  describe('VkAdapterClientMessage', () => {
    it('keepsClientMessagesIsolatedBetweenAdapters', 0, () => {
      const firstMessages: Array<string | undefined> = [];
      const secondMessages: Array<string | undefined> = [];
      const first: VkAdapter = new VkAdapter({
        onClientMessage: (fragment?: string): void => {
          firstMessages.push(fragment);
        }
      });
      const second: VkAdapter = new VkAdapter({
        onClientMessage: (fragment?: string): void => {
          secondMessages.push(fragment);
        }
      });

      first.emitClientMessage('one');
      second.emitClientMessage(undefined);

      expect(JSON.stringify(firstMessages)).assertEqual('["one"]');
      expect(secondMessages.length).assertEqual(1);
      expect(secondMessages[0] === undefined).assertTrue();
    });

    it('wrapsOrdinaryHostCallbackFailuresAsVkUnknownErrors', 0, () => {
      const adapter: VkAdapter = new VkAdapter({
        onClientMessage: (_fragment?: string): void => {
          throw new Error('host failure');
        }
      });
      let errorCode: string = '';

      try {
        adapter.emitClientMessage('example');
      } catch (error) {
        errorCode = vkClientCode(error as Object);
      }

      expect(errorCode).assertEqual('1');
    });

    it('doesNotLeakHostMiniAppErrorCodes', 0, () => {
      const adapter: VkAdapter = new VkAdapter({
        onClientMessage: (_fragment?: string): void => {
          throw new MiniAppError('HOST_PRIVATE_ERROR', 'private');
        }
      });
      let errorCode: string = '';

      try {
        adapter.emitClientMessage('example');
      } catch (error) {
        errorCode = vkClientCode(error as Object);
      }

      expect(errorCode).assertEqual('1');
    });
  });
}
