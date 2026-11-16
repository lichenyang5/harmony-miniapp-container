import { Permissions } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import {
  PermissionChecker,
  PermissionContract,
  PermissionTools,
  VkGrantedPermission
} from '../main/ets/capabilities/permissions/PermissionTools';

class RecordingPermissionChecker implements PermissionChecker {
  readonly checkedPermissions: Permissions[] = [];
  private readonly grantedPermissions: Permissions[];

  constructor(grantedPermissions: Permissions[]) {
    this.grantedPermissions = grantedPermissions;
  }

  isGranted(permission: Permissions): boolean {
    this.checkedPermissions.push(permission);
    return this.grantedPermissions.indexOf(permission) >= 0;
  }
}

export default function permissionToolsTest(): void {
  describe('PermissionTools', () => {
    it('mapsGrantedHarmonyPermissionsToUniqueVkNames', 0, () => {
      const granted: Permissions[] = [
        'ohos.permission.CAMERA',
        'ohos.permission.LOCATION',
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.READ_IMAGEVIDEO',
        'ohos.permission.WRITE_IMAGEVIDEO'
      ];

      const permissions: VkGrantedPermission[] = PermissionContract.toVkPermissions(granted);

      expect(JSON.stringify(permissions)).assertEqual('["camera","location","photo"]');
    });

    it('queriesHarmonyPermissionsAndReturnsGrantedVkNames', 0, () => {
      const checker: RecordingPermissionChecker = new RecordingPermissionChecker([
        'ohos.permission.CAMERA',
        'ohos.permission.APPROXIMATELY_LOCATION'
      ]);
      const tools: PermissionTools = new PermissionTools(100, checker);

      const permissions: VkGrantedPermission[] = tools.getGrantedPermissions();

      expect(JSON.stringify(permissions)).assertEqual('["camera","location"]');
      expect(checker.checkedPermissions.length).assertEqual(5);
    });
  });
}
