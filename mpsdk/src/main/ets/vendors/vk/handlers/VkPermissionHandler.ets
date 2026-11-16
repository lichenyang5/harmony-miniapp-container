import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import {
  PermissionProvider,
  PermissionTools,
  VkGrantedPermission
} from '../../../capabilities/permissions/PermissionTools';
import { BridgeContext } from '../../../core/Runtime';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';

export const VK_WEB_APP_GET_GRANTED_PERMISSIONS: string = 'VKWebAppGetGrantedPermissions';

interface VkGrantedPermissionsResult {
  permissions: VkGrantedPermission[];
}

/** 只负责把 HarmonyOS 已授权权限转换为 VK 返回数据。 */
export class VkPermissionHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly permissionTools: PermissionProvider;

  constructor(context: BridgeContext, permissionTools?: PermissionProvider) {
    this.context = context;
    this.permissionTools = permissionTools ??
      new PermissionTools(context.uiAbilityContext.applicationInfo.accessTokenId);
  }

  @VkEvent({ name: VK_WEB_APP_GET_GRANTED_PERMISSIONS })
  async getGrantedPermissions(params: object): Promise<VkGrantedPermissionsResult> {
    ParamAssert.assertObject(params, 'params');
    try {
      const result: VkGrantedPermissionsResult = {
        permissions: this.permissionTools.getGrantedPermissions()
      };
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  dispose(): void {
  }
}
