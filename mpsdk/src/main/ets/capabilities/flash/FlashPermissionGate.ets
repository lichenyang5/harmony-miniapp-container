import {
  abilityAccessCtrl, common, PermissionRequestResult, Permissions
} from '@kit.AbilityKit';
import { promptAction, window } from '@kit.ArkUI';
import { MiniAppError } from '../../core/MiniAppError';
import {
  PERMISSION_DENIED, SYSTEM_ERROR, USER_CANCELLED
} from '../../core/MiniAppErrorCode';

const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';

/** 解析单个相机权限请求；无效结果属于系统或宿主配置错误。 */
export function parseCameraPermissionResult(result: PermissionRequestResult): boolean {
  if (result.permissions.length !== 1 || result.permissions[0] !== CAMERA_PERMISSION ||
    result.authResults.length !== 1) {
    throw new MiniAppError(SYSTEM_ERROR, '相机权限请求返回结构无效');
  }
  const status: number = result.authResults[0];
  if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
    return true;
  }
  if (status === abilityAccessCtrl.GrantStatus.PERMISSION_DENIED) {
    return false;
  }
  throw new MiniAppError(SYSTEM_ERROR, `相机权限请求返回无效状态：${status}`);
}

/** 隔离业务确认弹窗和 HarmonyOS 权限请求，便于验证两层授权流程。 */
export interface CameraPermissionGateway {
  hasPermission(): boolean;

  confirmAccess(): Promise<boolean>;

  requestPermission(): Promise<boolean>;
}

/** 闪光灯开关使用的最小权限门禁。 */
export interface FlashPermissionProvider {
  ensureAllowed(enabled: boolean): Promise<void>;
}

/** 先执行 SDK 确认，再执行系统相机权限请求。 */
export class FlashPermissionGate implements FlashPermissionProvider {
  private readonly gateway: CameraPermissionGateway;
  private pending?: Promise<void>;

  constructor(gateway: CameraPermissionGateway) {
    this.gateway = gateway;
  }

  ensureAllowed(enabled: boolean): Promise<void> {
    if (!enabled) {
      return Promise.resolve();
    }
    if (this.pending) {
      return this.pending;
    }
    if (this.gateway.hasPermission()) {
      return Promise.resolve();
    }
    const operation: Promise<void> = this.requestAccess();
    this.pending = operation;
    operation.then((): void => {
      this.clearPending(operation);
    }, (): void => {
      this.clearPending(operation);
    });
    return operation;
  }

  private async requestAccess(): Promise<void> {
    const confirmed: boolean = await this.gateway.confirmAccess();
    if (!confirmed) {
      throw new MiniAppError(USER_CANCELLED, '用户拒绝开启相机闪光灯');
    }
    const granted: boolean = await this.gateway.requestPermission();
    if (!granted) {
      throw new MiniAppError(PERMISSION_DENIED, '相机权限被拒绝');
    }
  }

  private clearPending(operation: Promise<void>): void {
    if (this.pending === operation) {
      this.pending = undefined;
    }
  }
}

/** HarmonyOS 原生确认弹窗及运行时相机权限实现。 */
export class HarmonyCameraPermissionGateway implements CameraPermissionGateway {
  private readonly context: common.UIAbilityContext;
  private readonly manager: abilityAccessCtrl.AtManager;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.manager = abilityAccessCtrl.createAtManager();
  }

  hasPermission(): boolean {
    try {
      return this.manager.checkAccessTokenSync(
        this.context.applicationInfo.accessTokenId, CAMERA_PERMISSION) ===
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, '查询相机权限失败');
    }
  }

  async confirmAccess(): Promise<boolean> {
    try {
      const appWindow: window.Window = await window.getLastWindow(this.context);
      const response: promptAction.ShowDialogSuccessResponse =
        await appWindow.getUIContext().getPromptAction().showDialog({
          message: 'Allow access to your camera to enable camera flash',
          buttons: [
            { text: 'ALLOW', color: '#0A59F7', primary: true },
            { text: 'DENY', color: '#0A59F7' }
          ]
        });
      return response.index === 0;
    } catch (error) {
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, '显示相机访问确认失败');
    }
  }

  async requestPermission(): Promise<boolean> {
    try {
      const result: PermissionRequestResult =
        await this.manager.requestPermissionsFromUser(this.context, [CAMERA_PERMISSION]);
      return parseCameraPermissionResult(result);
    } catch (error) {
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, '申请相机权限失败');
    }
  }
}
