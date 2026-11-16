import { AbilityLifecycleCallback, common, UIAbility } from '@kit.AbilityKit';
import { HostLifecycleMonitor } from '../main/ets/core/HostLifecycleMonitor';

let lifecycle: AbilityLifecycleCallback | undefined;

/** 使用真实监视器，只替换系统的监听注册边界。 */
export function getTestLifecycle(): AbilityLifecycleCallback {
  HostLifecycleMonitor.initialize((callback: AbilityLifecycleCallback): number => {
    lifecycle = callback;
    return 0;
  });
  if (!lifecycle) {
    throw new Error('Test lifecycle listener is unavailable');
  }
  return lifecycle;
}

export function testAbility(context: common.UIAbilityContext): UIAbility {
  const ability = new UIAbility();
  ability.context = context;
  return ability;
}
