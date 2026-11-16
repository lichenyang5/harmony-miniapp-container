import { VK_VENDOR_ID } from '../main/ets/vendors/vk/VkVendor';
import { VendorAdapter } from '../main/ets/core/VendorAdapter';
import { TestVendorAdapter } from './TestVendorAdapter';
import { VkEventRegistry } from '../main/ets/vendors/vk/events/VkEventRegistry';
import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { SESSION_CLOSED, WEB_NOT_ATTACHED } from '../main/ets/core/MiniAppErrorCode';
import {
  BridgeContext,
  BridgeInjection,
  DocumentScript,
  MiniAppDescriptor,
  MiniAppSession,
  SwipeBackController,
  Vendor,
  VendorBinding
} from '../main/ets/core/Runtime';
import {
  VkAudioHandler
} from '../main/ets/vendors/vk/handlers/VkAudioHandler';
import { EmptyParams, getTestUiAbilityContext } from './TestContext';

class AudioTestContext implements BridgeContext {
  readonly id: string = 'audio-test';
  readonly appId: string = 'audio-test-app';
  readonly vendorId: string = VK_VENDOR_ID;
  readonly uiAbilityContext: common.UIAbilityContext = getTestUiAbilityContext();
  pauseCount: number = 0;
  shouldFail: boolean = false;

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
    this.pauseCount++;
    if (this.shouldFail) {
      throw new Error('pause failed');
    }
  }

  setSwipeBackEnabled(_enabled: boolean): void {
  }
}

class EmptyVendorBinding implements VendorBinding {
  injections: BridgeInjection[] = [];
  scripts: DocumentScript[] = [];

  onDocumentChanged(_documentId: number): void {
  }

  dispose(): void {
  }
}

class EmptyVendor implements Vendor {
  readonly vendorId: string = 'audio-test-vendor';

  createDefaultAdapter(): VendorAdapter {
    return new TestVendorAdapter(this.vendorId);
  }

  createBinding(_session: MiniAppSession): VendorBinding {
    return new EmptyVendorBinding();
  }
}

class AudioNoopSwipeBackController implements SwipeBackController {
  setEnabled(_enabled: boolean): void {
  }

  dispose(): void {
  }
}

function createAudioSession(): MiniAppSession {
  const descriptor: MiniAppDescriptor = {
    info: { appId: 'audio-test-app', vendor: 'audio-test-vendor', url: 'https://example.com' },
    vendor: new EmptyVendor(),
    adapter: new TestVendorAdapter('audio-test-vendor'),
    swipeBackController: new AudioNoopSwipeBackController()
  };
  return new MiniAppSession(
    'audio-session-test', descriptor, getTestUiAbilityContext());
}

export default function vkAudioHandlerTest(): void {
  describe('VkAudioHandler', () => {
    it('pausesCurrentWebMediaAndReturnsVkResult', 0, async () => {
      const context: AudioTestContext = new AudioTestContext();
      const handler: VkAudioHandler = new VkAudioHandler(context);

      const result = await handler.pauseAudio(new EmptyParams());

      expect(context.pauseCount).assertEqual(1);
      expect(result.result).assertTrue();
    });

    it('rejectsUnsupportedMethodBeforeCallingNativeTool', 0, async () => {
      const context: AudioTestContext = new AudioTestContext();
      const handler: VkAudioHandler = new VkAudioHandler(context);
      const registry = new VkEventRegistry(context);
      registry.initHandler([handler]);

      expect(registry.getHandler('VKWebAppAudioStop') === undefined).assertTrue();
      registry.dispose();
      expect(context.pauseCount).assertEqual(0);
    });

    it('propagatesNativePauseFailure', 0, async () => {
      const context: AudioTestContext = new AudioTestContext();
      context.shouldFail = true;
      const handler: VkAudioHandler = new VkAudioHandler(context);
      let rejected: boolean = false;

      try {
        await handler.pauseAudio(new EmptyParams());
      } catch (_) {
        rejected = true;
      }

      expect(rejected).assertTrue();
      expect(context.pauseCount).assertEqual(1);
    });

    it('reportsWebNotAttachedBeforeNativePause', 0, () => {
      const session: MiniAppSession = createAudioSession();
      let errorCode: string = '';

      try {
        session.pauseAllMedia();
      } catch (error) {
        errorCode = (error as MiniAppError).code;
      }

      expect(errorCode).assertEqual(WEB_NOT_ATTACHED);
      session.close();
    });

    it('reportsSessionClosedBeforeNativePause', 0, () => {
      const session: MiniAppSession = createAudioSession();
      session.close();
      let errorCode: string = '';

      try {
        session.pauseAllMedia();
      } catch (error) {
        errorCode = (error as MiniAppError).code;
      }

      expect(errorCode).assertEqual(SESSION_CLOSED);
    });
  });
}
