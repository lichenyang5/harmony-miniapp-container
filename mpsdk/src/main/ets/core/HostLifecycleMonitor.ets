import { AbilityLifecycleCallback, common, UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { MiniAppError } from './MiniAppError';
import { APP_IN_BACKGROUND, HOST_LIFECYCLE_INIT_FAILED, HOST_LIFECYCLE_NOT_INITIALIZED } from './MiniAppErrorCode';
import { SdkLogger } from '../logging/SdkLogger';

const TAG: string = 'HostLifecycle';

/** 内部平台订阅边界，避免将 ApplicationContext 保存在每个会话中。 */
export type LifecycleRegistrar = (callback: AbilityLifecycleCallback) => number;

/** 内部会话订阅，不从 HAR 导出。 */
export interface HostLifecycleObserver {
  onForegroundChanged(foreground: boolean): void;
  onDestroyed(): void;
}

interface HostLifecycleSubscription {
  observer?: HostLifecycleObserver;
}

/** 应用级监听与状态归属集中在此；监听随进程保留，销毁宿主只删除其记录。 */
export class HostLifecycleMonitor extends AbilityLifecycleCallback {
  private static instance?: HostLifecycleMonitor;
  private static readonly subscriptions: Map<common.UIAbilityContext, Set<HostLifecycleSubscription>> =
    new Map<common.UIAbilityContext, Set<HostLifecycleSubscription>>();
  private static readonly destroyedContexts: WeakSet<common.UIAbilityContext> =
    new WeakSet<common.UIAbilityContext>();
  private readonly foregroundStates: Map<common.UIAbilityContext, boolean> =
    new Map<common.UIAbilityContext, boolean>();

  private constructor() {
    super();
  }

  static initialize(register: LifecycleRegistrar): void {
    if (HostLifecycleMonitor.instance) {
      SdkLogger.debug(TAG, 'initializationSkipped');
      return;
    }
    const monitor = new HostLifecycleMonitor();
    SdkLogger.info(TAG, 'initializing');
    try {
      register(monitor);
    } catch (error) {
      const failure =
        new MiniAppError(HOST_LIFECYCLE_INIT_FAILED, 'Host lifecycle subscription failed', error as Object);
      SdkLogger.error(TAG, 'initializationFailed', failure);
      throw failure;
    }
    HostLifecycleMonitor.instance = monitor;
    SdkLogger.info(TAG, 'initialized');
  }

  static assertForeground(context: common.UIAbilityContext): void {
    const foreground = HostLifecycleMonitor.instance?.foregroundStates.get(context);
    if (foreground === undefined) {
      SdkLogger.warn(TAG, 'stateUnavailable', { code: HOST_LIFECYCLE_NOT_INITIALIZED });
      throw new MiniAppError(HOST_LIFECYCLE_NOT_INITIALIZED, 'Host lifecycle is not initialized');
    }
    if (!foreground) {
      SdkLogger.warn(TAG, 'foregroundRequired', { code: APP_IN_BACKGROUND });
      throw new MiniAppError(APP_IN_BACKGROUND, 'Host UIAbility is not in the foreground');
    }
  }

  /** 先登记再同步交付快照；未知宿主保持后台，初始化后沿用同一组订阅。 */
  static observe(context: common.UIAbilityContext, observer: HostLifecycleObserver): () => void {
    const subscription: HostLifecycleSubscription = { observer };
    if (HostLifecycleMonitor.destroyedContexts.has(context)) {
      HostLifecycleMonitor.notifyDestroyed(subscription);
      return (): void => {};
    }
    let subscriptions = HostLifecycleMonitor.subscriptions.get(context);
    if (!subscriptions) {
      subscriptions = new Set<HostLifecycleSubscription>();
      HostLifecycleMonitor.subscriptions.set(context, subscriptions);
    }
    subscriptions.add(subscription);
    HostLifecycleMonitor.notifyForeground(subscription,
      HostLifecycleMonitor.instance?.foregroundStates.get(context) === true);
    return (): void => {
      subscription.observer = undefined;
      const current = HostLifecycleMonitor.subscriptions.get(context);
      current?.delete(subscription);
      if (current?.size === 0) {
        HostLifecycleMonitor.subscriptions.delete(context);
      }
    };
  }

  onAbilityCreate(ability: UIAbility): void {
    if (HostLifecycleMonitor.destroyedContexts.has(ability.context)) {
      return;
    }
    if (!this.foregroundStates.has(ability.context)) {
      this.foregroundStates.set(ability.context, false);
      SdkLogger.info(TAG, 'hostCreated', { count: this.foregroundStates.size });
    } else {
      SdkLogger.debug(TAG, 'duplicateCreateIgnored');
    }
  }

  onAbilityForeground(ability: UIAbility): void {
    this.update(ability.context, true, 'onAbilityForeground');
  }

  onAbilityWillBackground(ability: UIAbility): void {
    this.update(ability.context, false, 'onAbilityWillBackground');
  }

  onAbilityBackground(ability: UIAbility): void {
    this.update(ability.context, false, 'onAbilityBackground');
  }

  onAbilityWillDestroy(ability: UIAbility): void {
    this.remove(ability.context, 'onAbilityWillDestroy');
  }

  onAbilityDestroy(ability: UIAbility): void {
    this.remove(ability.context, 'onAbilityDestroy');
  }

  onWindowStageCreate(_ability: UIAbility, _windowStage: window.WindowStage): void {
  }

  onWindowStageActive(_ability: UIAbility, _windowStage: window.WindowStage): void {
  }

  onWindowStageInactive(_ability: UIAbility, _windowStage: window.WindowStage): void {
  }

  onWindowStageDestroy(_ability: UIAbility, _windowStage: window.WindowStage): void {
  }

  onAbilityContinue(_ability: UIAbility): void {
  }

  private update(context: common.UIAbilityContext, foreground: boolean, callback: string): void {
    SdkLogger.debug(TAG, callback, { count: this.foregroundStates.size });
    // 只有创建事件能建立记录，销毁后的迟到前后台通知不能复活宿主。
    const previous = this.foregroundStates.get(context);
    if (previous === undefined) {
      SdkLogger.debug(TAG, 'notificationIgnored', { code: HOST_LIFECYCLE_NOT_INITIALIZED });
      return;
    }
    this.foregroundStates.set(context, foreground);
    if (previous !== foreground) {
      SdkLogger.info(TAG, foreground ? 'hostForeground' : 'hostBackground', { count: this.foregroundStates.size });
      const subscriptions = HostLifecycleMonitor.subscriptions.get(context);
      if (subscriptions) {
        for (const subscription of Array.from(subscriptions)) {
          // 回调可能关闭会话或销毁宿主，不交付已失效的前台通知。
          if (this.foregroundStates.get(context) !== foreground) {
            break;
          }
          HostLifecycleMonitor.notifyForeground(subscription, foreground);
        }
      }
    }
  }

  private remove(context: common.UIAbilityContext, callback: string): void {
    SdkLogger.debug(TAG, callback, { count: this.foregroundStates.size });
    HostLifecycleMonitor.destroyedContexts.add(context);
    if (this.foregroundStates.delete(context)) {
      SdkLogger.info(TAG, 'hostDestroyed', { count: this.foregroundStates.size });
    }
    const subscriptions = HostLifecycleMonitor.subscriptions.get(context);
    HostLifecycleMonitor.subscriptions.delete(context);
    if (subscriptions) {
      for (const subscription of subscriptions) {
        HostLifecycleMonitor.notifyDestroyed(subscription);
      }
    }
  }

  private static notifyForeground(subscription: HostLifecycleSubscription, foreground: boolean): void {
    try {
      subscription.observer?.onForegroundChanged(foreground);
    } catch (_) {
      SdkLogger.warn(TAG, 'foregroundObserverFailed');
    }
  }

  private static notifyDestroyed(subscription: HostLifecycleSubscription): void {
    const observer = subscription.observer;
    subscription.observer = undefined;
    try {
      observer?.onDestroyed();
    } catch (_) {
      SdkLogger.warn(TAG, 'destroyObserverFailed');
    }
  }
}

/** 厂商无关的能力门禁，不从 HAR 导出。 */
export function assertHostForeground(context: common.UIAbilityContext): void {
  HostLifecycleMonitor.assertForeground(context);
}
