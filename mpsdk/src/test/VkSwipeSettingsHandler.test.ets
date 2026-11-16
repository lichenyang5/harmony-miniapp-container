import { MiniAppError } from '../main/ets/core/MiniAppError';
import { vkClientCode } from './VkErrorTestUtils';
import { VK_VENDOR_ID } from '../main/ets/vendors/vk/VkVendor';
import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import { BridgeContext } from '../main/ets/core/Runtime';
import {
  VkSwipeSettingsHandler,
  VkSwipeSettingsParams
} from '../main/ets/vendors/vk/handlers/VkSwipeSettingsHandler';
import { getTestUiAbilityContext } from './TestContext';

class RecordingSwipeSettingsContext implements BridgeContext {
  readonly id: string = 'swipe-settings-handler-test';
  readonly appId: string = '54769936';
  readonly vendorId: string = VK_VENDOR_ID;
  readonly uiAbilityContext: common.UIAbilityContext = getTestUiAbilityContext();
  settings: boolean[] = [];

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

  setSwipeBackEnabled(enabled: boolean): void {
    this.settings.push(enabled);
  }
}

async function captureErrorCode(handler: VkSwipeSettingsHandler, paramsJson: string): Promise<string> {
  try {
    await handler.setSwipeSettings(JSON.parse(paramsJson) as VkSwipeSettingsParams);
  } catch (error) {
    return error instanceof MiniAppError &&
      (error.code === 'INVALID_ARGUMENT' || error.code === 'MISSING_REQUIRED_PARAMS') ? error.code :
      vkClientCode(error as Object);
  }
  return '';
}

export default function vkSwipeSettingsHandlerTest(): void {
  describe('VkSwipeSettingsHandler', () => {
    it('enablesNativeSwipeForFirstPanelAndReturnsVkResult', 0, async () => {
      const context: RecordingSwipeSettingsContext = new RecordingSwipeSettingsContext();
      const handler: VkSwipeSettingsHandler = new VkSwipeSettingsHandler(context);

      const result = await handler.setSwipeSettings({ history: true });

      expect(JSON.stringify(context.settings)).assertEqual('[true]');
      expect(result.result).assertTrue();
    });

    it('disablesNativeSwipeForInnerPanelAndReturnsVkResult', 0, async () => {
      const context: RecordingSwipeSettingsContext = new RecordingSwipeSettingsContext();
      const handler: VkSwipeSettingsHandler = new VkSwipeSettingsHandler(context);

      const result = await handler.setSwipeSettings({ history: false });

      expect(JSON.stringify(context.settings)).assertEqual('[false]');
      expect(result.result).assertTrue();
    });

    it('rejectsMissingHistoryBeforeNativeCall', 0, async () => {
      const context: RecordingSwipeSettingsContext = new RecordingSwipeSettingsContext();
      const handler: VkSwipeSettingsHandler = new VkSwipeSettingsHandler(context);

      const errorCode: string = await captureErrorCode(handler, '{}');

      expect(errorCode).assertEqual('MISSING_REQUIRED_PARAMS');
      expect(context.settings.length).assertEqual(0);
    });

    it('rejectsNonBooleanHistoryBeforeNativeCall', 0, async () => {
      const context: RecordingSwipeSettingsContext = new RecordingSwipeSettingsContext();
      const handler: VkSwipeSettingsHandler = new VkSwipeSettingsHandler(context);

      const errorCode: string = await captureErrorCode(handler, '{"history":"true"}');

      expect(errorCode).assertEqual('INVALID_ARGUMENT');
      expect(context.settings.length).assertEqual(0);
    });
  });
}
