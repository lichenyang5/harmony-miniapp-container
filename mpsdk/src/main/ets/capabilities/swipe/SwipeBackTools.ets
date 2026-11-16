import { deviceInfo } from '@kit.BasicServicesKit';
import { MiniAppError } from '../../core/MiniAppError';
import { NOT_SUPPORTED, SESSION_CLOSED, SYSTEM_ERROR } from '../../core/MiniAppErrorCode';
import { SwipeBackController } from '../../core/VendorAdapter';

/** 实际写入 HarmonyOS 原生侧滑开关的函数。 */
export type SwipeBackApplier = (enabled: boolean) => void;

interface SwipeBackContextGroup {
  scope: Object;
  apply: SwipeBackApplier;
  controllers: SwipeBackTools[];
}

/**
 * UIContext 级侧滑返回协调器。
 * 最后一次成功设置的控制器拥有原生状态；所有 SDK 控制器释放后恢复默认开启。
 */
export class SwipeBackTools implements SwipeBackController {
  private static readonly MIN_SUPPORTED_API: number = 18;
  private static readonly CONTEXT_GROUPS: SwipeBackContextGroup[] = [];
  private readonly scope: Object;
  private readonly apply: SwipeBackApplier;
  private readonly sdkApiVersion: number;
  private group?: SwipeBackContextGroup;
  private requestedEnabled?: boolean;
  private disposed: boolean = false;

  constructor(scope: Object, apply: SwipeBackApplier, sdkApiVersion: number = deviceInfo.sdkApiVersion) {
    this.scope = scope;
    this.apply = apply;
    this.sdkApiVersion = sdkApiVersion;
  }

  private static getOrCreateGroup(scope: Object, apply: SwipeBackApplier): SwipeBackContextGroup {
    for (let index: number = 0; index < SwipeBackTools.CONTEXT_GROUPS.length; index++) {
      const group: SwipeBackContextGroup = SwipeBackTools.CONTEXT_GROUPS[index];
      if (group.scope === scope) {
        return group;
      }
    }
    const group: SwipeBackContextGroup = {
      scope,
      apply,
      controllers: []
    };
    SwipeBackTools.CONTEXT_GROUPS.push(group);
    return group;
  }

  private static removeGroupIfUnused(group: SwipeBackContextGroup): void {
    if (group.controllers.length > 0) {
      return;
    }
    const groupIndex: number = SwipeBackTools.CONTEXT_GROUPS.indexOf(group);
    if (groupIndex >= 0) {
      SwipeBackTools.CONTEXT_GROUPS.splice(groupIndex, 1);
    }
  }

  setEnabled(enabled: boolean): void {
    if (this.disposed) {
      throw new MiniAppError(SESSION_CLOSED, '侧滑返回控制器已释放');
    }
    if (this.sdkApiVersion < SwipeBackTools.MIN_SUPPORTED_API) {
      throw new MiniAppError(NOT_SUPPORTED, '当前系统版本不支持原生侧滑返回设置');
    }

    const group: SwipeBackContextGroup = SwipeBackTools.getOrCreateGroup(this.scope, this.apply);
    try {
      group.apply(enabled);
    } catch (error) {
      SwipeBackTools.removeGroupIfUnused(group);
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, '设置原生侧滑返回失败');
    }

    const previousIndex: number = group.controllers.indexOf(this);
    if (previousIndex >= 0) {
      group.controllers.splice(previousIndex, 1);
    }
    this.group = group;
    this.requestedEnabled = enabled;
    group.controllers.push(this);
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    const group: SwipeBackContextGroup | undefined = this.group;
    this.group = undefined;
    this.requestedEnabled = undefined;
    if (!group) {
      return;
    }

    const controllerIndex: number = group.controllers.indexOf(this);
    if (controllerIndex < 0) {
      return;
    }
    const wasOwner: boolean = controllerIndex === group.controllers.length - 1;
    group.controllers.splice(controllerIndex, 1);
    if (!wasOwner) {
      return;
    }

    const owner: SwipeBackTools | undefined = group.controllers[group.controllers.length - 1];
    const restoreEnabled: boolean = owner?.requestedEnabled ?? true;
    try {
      group.apply(restoreEnabled);
    } catch (error) {
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, '恢复原生侧滑返回失败');
    } finally {
      SwipeBackTools.removeGroupIfUnused(group);
    }
  }
}
