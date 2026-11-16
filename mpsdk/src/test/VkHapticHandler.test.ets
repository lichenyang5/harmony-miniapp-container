import { VkEventRegistry } from '../main/ets/vendors/vk/events/VkEventRegistry';
import { VkTestContext } from './TestContext';
import { describe, expect, it } from '@ohos/hypium';
import { HapticEffectConfig } from '../main/ets/capabilities/haptic/HapticTools';
import {
  VK_WEB_APP_TAPTIC_IMPACT_OCCURRED,
  VK_WEB_APP_TAPTIC_NOTIFICATION_OCCURRED,
  VK_WEB_APP_TAPTIC_SELECTION_CHANGED,
  VkHapticHandler
} from '../main/ets/vendors/vk/handlers/VkHapticHandler';

export default function vkHapticHandlerTest(): void {
  describe('VkHapticHandler', () => {
    it('exposesOnlyHapticMethods', 0, () => {
      const handler = new VkHapticHandler(new VkTestContext());
      const registry = new VkEventRegistry(handler.context);
      registry.initHandler([handler]);
      const methods = registry.getSupportedHandlers();

      expect(methods.length).assertEqual(3);
      expect(registry.getHandler(VK_WEB_APP_TAPTIC_IMPACT_OCCURRED) !== undefined).assertTrue();
      expect(registry.getHandler(VK_WEB_APP_TAPTIC_NOTIFICATION_OCCURRED) !== undefined).assertTrue();
      expect(registry.getHandler(VK_WEB_APP_TAPTIC_SELECTION_CHANGED) !== undefined).assertTrue();
      expect(registry.getHandler('VKWebAppFlashSetLevel') !== undefined).assertFalse();
      registry.dispose();
    });

    it('mapsImpactStyleBeforeCallingNativeTool', 0, async () => {
      let received: HapticEffectConfig | undefined;
      const handler = new VkHapticHandler(new VkTestContext(), async (config: HapticEffectConfig): Promise<void> => {
        received = config;
      });

      const result = await handler.impactOccurred({ style: 'medium' });

      expect(received?.effectId).assertEqual('haptic.effect.hard');
      expect(received?.intensity).assertEqual(65);
      expect(result.result).assertTrue();
    });

    it('rejectsUnknownHapticParameterBeforeCallingNativeTool', 0, async () => {
      let called = false;
      const handler = new VkHapticHandler(new VkTestContext(), async (_config: HapticEffectConfig): Promise<void> => {
        called = true;
      });
      let rejected = false;

      try {
        await handler.notificationOccurred({ type: 'unknown' });
      } catch (_) {
        rejected = true;
      }

      expect(rejected).assertTrue();
      expect(called).assertFalse();
    });
  });
}
