import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { assertHostForeground } from '../../core/HostLifecycleMonitor';

/** 可替换的系统权限边界，不包含厂商和网页策略。 */
export interface SystemPermissionAccess {
  has(permission: Permissions): boolean;

  request(permissions: Permissions[]): Promise<Permissions[]>;
}

class HarmonyPermissionAccess implements SystemPermissionAccess {
  private readonly context: common.UIAbilityContext;
  private readonly manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  has(permission: Permissions): boolean {
    return this.manager.checkAccessTokenSync(this.context.applicationInfo.accessTokenId, permission) ===
      abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  async request(permissions: Permissions[]): Promise<Permissions[]> {
    const result = await this.manager.requestPermissionsFromUser(this.context, permissions);
    return permissions.filter((permission: Permissions): boolean => {
      const index = result.permissions.indexOf(permission);
      return index >= 0 && result.authResults[index] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    });
  }
}

/** 同一宿主的网页系统授权共用队列，排队期间失效的请求不再弹窗。 */
export class HarmonyPermissionRequester {
  private static queues: Map<common.UIAbilityContext, Promise<void>> = new Map();
  private readonly context: common.UIAbilityContext;
  private readonly access: SystemPermissionAccess;

  constructor(context: common.UIAbilityContext, access?: SystemPermissionAccess) {
    this.context = context;
    this.access = access ?? new HarmonyPermissionAccess(context);
  }

  assertForeground(): void {
    assertHostForeground(this.context);
  }

  request(permissions: Permissions[], isCurrent: () => boolean,
    requestTogether: boolean = false): Promise<Permissions[]> {
    const preceding = HarmonyPermissionRequester.queues.get(this.context) ?? Promise.resolve();
    const operation =
      preceding.then((): Promise<Permissions[]> => this.requestNow(permissions, isCurrent, requestTogether));
    const tail: Promise<void> = operation.then((): void => {
    }, (): void => {
    });
    HarmonyPermissionRequester.queues.set(this.context, tail);
    tail.then((): void => {
      if (HarmonyPermissionRequester.queues.get(this.context) === tail) {
        HarmonyPermissionRequester.queues.delete(this.context);
      }
    });
    return operation;
  }

  private async requestNow(permissions: Permissions[], isCurrent: () => boolean,
    requestTogether: boolean): Promise<Permissions[]> {
    if (!isCurrent()) {
      return [];
    }
    this.assertForeground();
    let granted = permissions.filter((permission: Permissions): boolean => this.access.has(permission));
    const missing = permissions.filter((permission: Permissions): boolean => !granted.includes(permission));
    if (missing.length > 0) {
      // 精确定位需与模糊定位一起申请，并以这次完整授权结果为准。
      if (requestTogether) {
        granted = await this.access.request(permissions);
      } else {
        granted.push(...await this.access.request(missing));
      }
    }
    if (!isCurrent()) {
      return [];
    }
    this.assertForeground();
    return granted;
  }
}
