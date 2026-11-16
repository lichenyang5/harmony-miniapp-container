import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';

/** VKWebAppGetGrantedPermissions 支持返回的权限名称。 */
export type VkGrantedPermission = 'camera' | 'location' | 'photo';

interface PermissionMapping {
  harmonyPermission: Permissions;
  vkPermission: VkGrantedPermission;
}

const PERMISSION_MAPPINGS: PermissionMapping[] = [
  { harmonyPermission: 'ohos.permission.CAMERA', vkPermission: 'camera' },
  { harmonyPermission: 'ohos.permission.LOCATION', vkPermission: 'location' },
  { harmonyPermission: 'ohos.permission.APPROXIMATELY_LOCATION', vkPermission: 'location' },
  { harmonyPermission: 'ohos.permission.READ_IMAGEVIDEO', vkPermission: 'photo' },
  { harmonyPermission: 'ohos.permission.WRITE_IMAGEVIDEO', vkPermission: 'photo' }
];

/** 为 VK Bridge 提供已授权权限，便于隔离系统权限查询与协议转换。 */
export interface PermissionProvider {
  getGrantedPermissions(): VkGrantedPermission[];
}

/** 读取单个 HarmonyOS 权限是否已授予。 */
export interface PermissionChecker {
  isGranted(permission: Permissions): boolean;
}

/** 已授权权限原生工具；只查询状态，不主动申请权限。 */
export class PermissionTools implements PermissionProvider {
  private readonly accessTokenId: number;
  private readonly checker?: PermissionChecker;

  constructor(accessTokenId: number, checker?: PermissionChecker) {
    this.accessTokenId = accessTokenId;
    this.checker = checker;
  }

  getGrantedPermissions(): VkGrantedPermission[] {
    const grantedHarmonyPermissions: Permissions[] = [];
    const manager = this.checker ? undefined : abilityAccessCtrl.createAtManager();
    PERMISSION_MAPPINGS.forEach((mapping: PermissionMapping): void => {
      const granted: boolean = this.checker ? this.checker.isGranted(mapping.harmonyPermission) :
        manager?.checkAccessTokenSync(this.accessTokenId, mapping.harmonyPermission) ===
          abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      if (granted) {
        grantedHarmonyPermissions.push(mapping.harmonyPermission);
      }
    });
    return PermissionContract.toVkPermissions(grantedHarmonyPermissions);
  }
}

/** HarmonyOS 权限到 VK 权限名称的纯映射规则。 */
export class PermissionContract {
  static toVkPermissions(grantedHarmonyPermissions: Permissions[]): VkGrantedPermission[] {
    const permissions: VkGrantedPermission[] = [];
    PERMISSION_MAPPINGS.forEach((mapping: PermissionMapping): void => {
      const granted: boolean = grantedHarmonyPermissions.indexOf(mapping.harmonyPermission) >= 0;
      if (granted && permissions.indexOf(mapping.vkPermission) < 0) {
        permissions.push(mapping.vkPermission);
      }
    });
    return permissions;
  }
}
