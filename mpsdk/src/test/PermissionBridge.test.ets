import { VkEventRegistry } from '../main/ets/vendors/vk/events/VkEventRegistry';
import { EmptyParams, VkTestContext } from './TestContext';
import { describe, expect, it } from '@ohos/hypium';
import {
  PermissionProvider, VkGrantedPermission
} from '../main/ets/capabilities/permissions/PermissionTools';
import {
  VK_WEB_APP_GET_GRANTED_PERMISSIONS,
  VkPermissionHandler
} from '../main/ets/vendors/vk/handlers/VkPermissionHandler';

class RecordingPermissionTools implements PermissionProvider {
  getGrantedPermissions(): VkGrantedPermission[] {
    return ['camera', 'photo'];
  }
}

export default function permissionBridgeTest(): void {
  describe('VkPermissionHandler', () => {
    it('exposesOnlyGrantedPermissionsMethod', 0, () => {
      const handler: VkPermissionHandler = new VkPermissionHandler(new VkTestContext(), new RecordingPermissionTools());

      const registry = new VkEventRegistry(handler.context);
      registry.initHandler([handler]);

      expect(registry.getSupportedHandlers().length).assertEqual(1);
      expect(registry.getHandler(VK_WEB_APP_GET_GRANTED_PERMISSIONS) !== undefined).assertTrue();
      expect(registry.getHandler('VKWebAppFlashGetInfo') === undefined).assertTrue();
      registry.dispose();
    });

    it('returnsGrantedPermissionsFromNativeProvider', 0, async () => {
      const handler: VkPermissionHandler = new VkPermissionHandler(new VkTestContext(), new RecordingPermissionTools());

      const result = await handler.getGrantedPermissions(new EmptyParams());
      const permissions = result.permissions;

      expect(JSON.stringify(permissions)).assertEqual('["camera","photo"]');
    });
  });
}
