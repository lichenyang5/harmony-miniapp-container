import { common, Permissions } from '@kit.AbilityKit';
import { HarmonyPermissionRequester, SystemPermissionAccess } from './HarmonyPermissionRequester';

const APPROXIMATE_LOCATION: Permissions = 'ohos.permission.APPROXIMATELY_LOCATION';
const PRECISE_LOCATION: Permissions = 'ohos.permission.LOCATION';

export interface GeolocationPermissionGateway {
  assertForeground(): void;

  request(isCurrent: () => boolean): Promise<boolean>;
}

/** 前台精确定位授权；仅有模糊位置权限时不放行网页定位。 */
export class HarmonyGeolocationPermissionGateway implements GeolocationPermissionGateway {
  private readonly requester: HarmonyPermissionRequester;

  constructor(context: common.UIAbilityContext, access?: SystemPermissionAccess) {
    this.requester = new HarmonyPermissionRequester(context, access);
  }

  assertForeground(): void {
    this.requester.assertForeground();
  }

  async request(isCurrent: () => boolean): Promise<boolean> {
    const granted = await this.requester.request([APPROXIMATE_LOCATION, PRECISE_LOCATION],
      isCurrent, true);
    return granted.includes(APPROXIMATE_LOCATION) && granted.includes(PRECISE_LOCATION);
  }
}
