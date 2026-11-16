import { common, Permissions } from '@kit.AbilityKit';
import { HarmonyPermissionRequester, SystemPermissionAccess } from '../permissions/HarmonyPermissionRequester';
import {
  WEB_AUDIO_CAPTURE,
  WEB_VIDEO_CAPTURE,
  WebMediaPermissionGateway
} from '../../web/WebMediaPermissionController';

const MICROPHONE: Permissions = 'ohos.permission.MICROPHONE';
const CAMERA: Permissions = 'ohos.permission.CAMERA';

/** 将网页媒体资源映射为系统权限，与网页定位共用宿主授权队列。 */
export class HarmonyMediaPermissionGateway implements WebMediaPermissionGateway {
  private readonly requester: HarmonyPermissionRequester;

  constructor(context: common.UIAbilityContext, access?: SystemPermissionAccess) {
    this.requester = new HarmonyPermissionRequester(context, access);
  }

  assertForeground(): void {
    this.requester.assertForeground();
  }

  async request(resources: string[], isCurrent: () => boolean): Promise<string[]> {
    if (resources.some(
      (resource: string): boolean => resource !== WEB_AUDIO_CAPTURE && resource !== WEB_VIDEO_CAPTURE)) {
      return [];
    }
    const permissions: Permissions[] = [];
    if (resources.includes(WEB_AUDIO_CAPTURE)) {
      permissions.push(MICROPHONE);
    }
    if (resources.includes(WEB_VIDEO_CAPTURE)) {
      permissions.push(CAMERA);
    }
    const granted = await this.requester.request(permissions, isCurrent);
    return resources.filter((resource: string): boolean => granted.includes(
      resource === WEB_AUDIO_CAPTURE ? MICROPHONE : CAMERA));
  }
}
