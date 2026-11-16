import { VK_VENDOR_ID } from '../main/ets/vendors/vk/VkVendor';
import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import {
  ViewSettings, ViewSettingsProvider
} from '../main/ets/capabilities/view/ViewSettingsTools';
import { BridgeContext } from '../main/ets/core/Runtime';
import {
  VkViewSettingsHandler
} from '../main/ets/vendors/vk/handlers/VkViewSettingsHandler';
import { getTestUiAbilityContext } from './TestContext';

class ViewSettingsTestContext implements BridgeContext {
  readonly id: string = 'view-settings-handler-test';
  readonly appId: string = '54769936';
  readonly vendorId: string = VK_VENDOR_ID;
  readonly uiAbilityContext: common.UIAbilityContext = getTestUiAbilityContext();
  private cleanups: Array<() => void> = [];

  send(_script: string): Promise<boolean> {
    return Promise.resolve(true);
  }

  getDocumentId(): number {
    return 1;
  }

  addCleanup(cleanup: () => void): void {
    this.cleanups.push(cleanup);
  }

  closeMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  openMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  pauseAllMedia(): void {
  }

  setSwipeBackEnabled(_enabled: boolean): void {
  }

  runCleanups(): void {
    const cleanups: Array<() => void> = this.cleanups;
    this.cleanups = [];
    cleanups.forEach((cleanup: () => void): void => cleanup());
  }
}

class RecordingViewSettingsProvider implements ViewSettingsProvider {
  applied?: ViewSettings;
  disposed: boolean = false;

  apply(settings: ViewSettings): Promise<void> {
    this.applied = settings;
    return Promise.resolve();
  }

  dispose(): void {
    this.disposed = true;
  }
}

export default function vkViewSettingsHandlerTest(): void {
  describe('VkViewSettingsHandler', () => {
    it('mapsOfficialFieldsAndReturnsVkResult', 0, async () => {
      const context: ViewSettingsTestContext = new ViewSettingsTestContext();
      const provider: RecordingViewSettingsProvider = new RecordingViewSettingsProvider();
      const handler: VkViewSettingsHandler =
        new VkViewSettingsHandler(context, (): ViewSettingsProvider => provider);

      const result = await handler.setViewSettings({
        status_bar_style: 'light',
        action_bar_color: '#112233',
        navigation_bar_color: '#445566'
      });

      expect(provider.applied?.statusBarStyle).assertEqual('light');
      expect(provider.applied?.actionBarColor).assertEqual('#112233');
      expect(provider.applied?.navigationBarColor).assertEqual('#445566');
      expect(result.result).assertTrue();
    });

    it('rejectsInvalidStatusBarStyleBeforeNativeCall', 0, async () => {
      const context: ViewSettingsTestContext = new ViewSettingsTestContext();
      const provider: RecordingViewSettingsProvider = new RecordingViewSettingsProvider();
      const handler: VkViewSettingsHandler =
        new VkViewSettingsHandler(context, (): ViewSettingsProvider => provider);
      let rejected: boolean = false;

      try {
        await handler.setViewSettings({ status_bar_style: 'blue' });
      } catch (_) {
        rejected = true;
      }

      expect(rejected).assertTrue();
      expect(provider.applied === undefined).assertTrue();
    });

    it('releasesPageProviderAndCreatesFreshInstance', 0, async () => {
      const context: ViewSettingsTestContext = new ViewSettingsTestContext();
      const created: RecordingViewSettingsProvider[] = [];
      const handler: VkViewSettingsHandler = new VkViewSettingsHandler(context,
        (): ViewSettingsProvider => {
          const provider: RecordingViewSettingsProvider = new RecordingViewSettingsProvider();
          created.push(provider);
          return provider;
        });

      await handler.setViewSettings({ status_bar_style: 'light' });
      context.runCleanups();
      await handler.setViewSettings({ status_bar_style: 'dark' });

      expect(created.length).assertEqual(2);
      expect(created[0].disposed).assertTrue();
      expect(created[1].disposed).assertFalse();
      handler.dispose();
      expect(created[1].disposed).assertTrue();
    });
  });
}
