import { VK_VENDOR_ID } from '../main/ets/vendors/vk/VkVendor';
import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import { FlashInfo, FlashInfoProvider } from '../main/ets/capabilities/flash/FlashTools';
import { BridgeContext } from '../main/ets/core/Runtime';
import { VkFlashHandler } from '../main/ets/vendors/vk/handlers/VkFlashHandler';
import { getTestUiAbilityContext } from './TestContext';

/** 为无业务字段的请求提供 ArkTS 可识别的具体类型。 */
class FlashInfoParams {
}

class RecordingBridgeContext implements BridgeContext {
  readonly id: string = 'flash-handler-test';
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
    const cleanups = this.cleanups;
    this.cleanups = [];
    cleanups.forEach((cleanup: () => void): void => cleanup());
  }
}

class RecordingFlashTools implements FlashInfoProvider {
  enabled: boolean = false;
  disposed: boolean = false;

  getInfo(): FlashInfo {
    return { isAvailable: true, level: this.enabled ? 1 : 0 };
  }

  setEnabled(enabled: boolean): Promise<void> {
    this.enabled = enabled;
    return Promise.resolve();
  }

  dispose(): void {
    this.disposed = true;
  }
}

class DeferredFlashTools implements FlashInfoProvider {
  enabled: boolean = false;
  private completeSet?: () => void;

  getInfo(): FlashInfo {
    return { isAvailable: true, level: this.enabled ? 1 : 0 };
  }

  setEnabled(enabled: boolean): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      this.completeSet = (): void => {
        this.enabled = enabled;
        resolve();
      };
    });
  }

  complete(): void {
    this.completeSet?.();
    this.completeSet = undefined;
  }

  dispose(): void {
  }
}

export default function flashBridgeTest(): void {
  describe('VkFlashHandler', () => {
    it('returnsVkFlashInfoPayload', 0, async () => {
      const context: RecordingBridgeContext = new RecordingBridgeContext();
      const tools: RecordingFlashTools = new RecordingFlashTools();
      const handler: VkFlashHandler = new VkFlashHandler(context, (): FlashInfoProvider => tools);

      const result = await handler.getFlashInfo(new FlashInfoParams());

      expect(result.is_available).assertTrue();
      expect(result.level).assertEqual(0);
      handler.dispose();
    });

    it('mapsPositiveLevelToNativeEnable', 0, async () => {
      const context: RecordingBridgeContext = new RecordingBridgeContext();
      const tools: RecordingFlashTools = new RecordingFlashTools();
      const handler: VkFlashHandler = new VkFlashHandler(context, (): FlashInfoProvider => tools);

      const result = await handler.setFlashLevel({ level: 0.5 });

      expect(tools.enabled).assertTrue();
      expect(result.result).assertTrue();
      handler.dispose();
    });

    it('mapsZeroLevelToNativeDisable', 0, async () => {
      const context: RecordingBridgeContext = new RecordingBridgeContext();
      const tools: RecordingFlashTools = new RecordingFlashTools();
      tools.enabled = true;
      const handler: VkFlashHandler = new VkFlashHandler(context, (): FlashInfoProvider => tools);

      await handler.setFlashLevel({ level: 0 });

      expect(tools.enabled).assertFalse();
      handler.dispose();
    });

    it('waitsForPermissionAndTorchOperationBeforeReturningSuccess', 0, async () => {
      const context: RecordingBridgeContext = new RecordingBridgeContext();
      const tools: DeferredFlashTools = new DeferredFlashTools();
      const handler: VkFlashHandler = new VkFlashHandler(context, (): FlashInfoProvider => tools);
      let settled: boolean = false;

      const request = handler.setFlashLevel({ level: 1 });
      request.then((_result: Object): void => {
        settled = true;
      });
      await Promise.resolve();

      expect(settled).assertFalse();
      tools.complete();
      const result = await request;
      expect(result.result).assertTrue();
      expect(tools.enabled).assertTrue();
      handler.dispose();
    });

    it('rejectsOutOfRangeLevelBeforeCallingNativeTool', 0, async () => {
      const context: RecordingBridgeContext = new RecordingBridgeContext();
      const tools: RecordingFlashTools = new RecordingFlashTools();
      const handler: VkFlashHandler = new VkFlashHandler(context, (): FlashInfoProvider => tools);
      let rejected: boolean = false;

      try {
        await handler.setFlashLevel({ level: 1.1 });
      } catch (_) {
        rejected = true;
      }

      expect(rejected).assertTrue();
      expect(tools.enabled).assertFalse();
      handler.dispose();
    });

    it('releasesPageScopedFlashToolsAndCreatesFreshInstance', 0, async () => {
      const context: RecordingBridgeContext = new RecordingBridgeContext();
      const created: RecordingFlashTools[] = [];
      const handler: VkFlashHandler = new VkFlashHandler(context, (): FlashInfoProvider => {
        const tools: RecordingFlashTools = new RecordingFlashTools();
        created.push(tools);
        return tools;
      });

      await handler.getFlashInfo(new FlashInfoParams());
      context.runCleanups();
      await handler.getFlashInfo(new FlashInfoParams());

      expect(created.length).assertEqual(2);
      expect(created[0].disposed).assertTrue();
      expect(created[1].disposed).assertFalse();
      handler.dispose();
      expect(created[1].disposed).assertTrue();
    });
  });
}
