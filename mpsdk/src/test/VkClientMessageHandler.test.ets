import { MiniAppError } from '../main/ets/core/MiniAppError';
import { vkClientCode } from './VkErrorTestUtils';
import { VK_VENDOR_ID } from '../main/ets/vendors/vk/VkVendor';
import { VkAdapter } from '../main/ets/vendors/vk/VkAdapter';
import { VkEventRegistry } from '../main/ets/vendors/vk/events/VkEventRegistry';
import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import { BridgeContext } from '../main/ets/core/Runtime';
import { VkClientMessageHandler, VkClientMessageParams } from '../main/ets/vendors/vk/handlers/VkClientMessageHandler';
import { getTestUiAbilityContext } from './TestContext';

class RecordingClientMessageContext implements BridgeContext {
  readonly id: string = 'client-message-handler-test';
  readonly appId: string = '54769936';
  readonly vendorId: string = VK_VENDOR_ID;
  readonly uiAbilityContext: common.UIAbilityContext = getTestUiAbilityContext();
  fragments: Array<string | undefined> = [];

  send(_script: string): Promise<boolean> {
    return Promise.resolve(true);
  }

  getDocumentId(): number {
    return 1;
  }

  addCleanup(_cleanup: () => void): void {
  }

  closeMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  openMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  pauseAllMedia(): void {
  }

  recordFragment(fragment?: string): void {
    this.fragments.push(fragment);
  }

  setSwipeBackEnabled(_enabled: boolean): void {
  }
}

async function captureErrorCode(handler: VkClientMessageHandler, paramsJson: string): Promise<string> {
  try {
    await handler.sendToClient(JSON.parse(paramsJson) as VkClientMessageParams);
  } catch (error) {
    return error instanceof MiniAppError && error.code === 'INVALID_ARGUMENT' ? error.code :
      vkClientCode(error as Object);
  }
  return '';
}

export default function vkClientMessageHandlerTest(): void {
  describe('VkClientMessageHandler', () => {
    it('rejectsMessagesAfterDisposeWithoutCallingHost', 0, async () => {
      const context: RecordingClientMessageContext = new RecordingClientMessageContext();
      const handler: VkClientMessageHandler = new VkClientMessageHandler(context, new VkAdapter({
        onClientMessage: (fragment?: string): void => context.recordFragment(fragment)
      }));
      handler.dispose();

      const errorCode: string = await captureErrorCode(handler, '{"fragment":"late"}');

      expect(errorCode).assertEqual('1');
      expect(context.fragments.length).assertEqual(0);
    });

    it('forwardsFragmentAndReturnsVkResult', 0, async () => {
      const context: RecordingClientMessageContext = new RecordingClientMessageContext();
      const handler: VkClientMessageHandler = new VkClientMessageHandler(context, new VkAdapter({
        onClientMessage: (fragment?: string): void => context.recordFragment(fragment)
      }));

      const result = await handler.sendToClient({ fragment: 'example' });

      expect(context.fragments.length).assertEqual(1);
      expect(context.fragments[0]).assertEqual('example');
      expect(result.result).assertTrue();
    });

    it('forwardsUndefinedWhenFragmentIsOmitted', 0, async () => {
      const context: RecordingClientMessageContext = new RecordingClientMessageContext();
      const handler: VkClientMessageHandler = new VkClientMessageHandler(context, new VkAdapter({
        onClientMessage: (fragment?: string): void => context.recordFragment(fragment)
      }));

      const params: VkClientMessageParams = {};
      const result = await handler.sendToClient(params);

      expect(context.fragments.length).assertEqual(1);
      expect(context.fragments[0] === undefined).assertTrue();
      expect(result.result).assertTrue();
    });

    it('forwardsEmptyFragmentAsAValidString', 0, async () => {
      const context: RecordingClientMessageContext = new RecordingClientMessageContext();
      const handler: VkClientMessageHandler = new VkClientMessageHandler(context, new VkAdapter({
        onClientMessage: (fragment?: string): void => context.recordFragment(fragment)
      }));

      await handler.sendToClient({ fragment: '' });

      expect(context.fragments.length).assertEqual(1);
      expect(context.fragments[0]).assertEqual('');
    });

    it('rejectsNumericFragmentBeforeCallingHost', 0, async () => {
      const context: RecordingClientMessageContext = new RecordingClientMessageContext();
      const handler: VkClientMessageHandler = new VkClientMessageHandler(context, new VkAdapter({
        onClientMessage: (fragment?: string): void => context.recordFragment(fragment)
      }));

      const errorCode: string = await captureErrorCode(handler, '{"fragment":1}');

      expect(errorCode).assertEqual('INVALID_ARGUMENT');
      expect(context.fragments.length).assertEqual(0);
    });

    it('rejectsNullFragmentBeforeCallingHost', 0, async () => {
      const context: RecordingClientMessageContext = new RecordingClientMessageContext();
      const handler: VkClientMessageHandler = new VkClientMessageHandler(context, new VkAdapter({
        onClientMessage: (fragment?: string): void => context.recordFragment(fragment)
      }));

      const errorCode: string = await captureErrorCode(handler, '{"fragment":null}');

      expect(errorCode).assertEqual('INVALID_ARGUMENT');
      expect(context.fragments.length).assertEqual(0);
    });

    it('rejectsUnsupportedMethodsBeforeCallingHost', 0, async () => {
      const context: RecordingClientMessageContext = new RecordingClientMessageContext();
      const handler: VkClientMessageHandler = new VkClientMessageHandler(context, new VkAdapter({
        onClientMessage: (fragment?: string): void => context.recordFragment(fragment)
      }));
      const registry = new VkEventRegistry(context);
      registry.initHandler([handler]);

      expect(registry.getHandler('VKWebAppUnknown') === undefined).assertTrue();
      registry.dispose();
      expect(context.fragments.length).assertEqual(0);
    });
  });
}
