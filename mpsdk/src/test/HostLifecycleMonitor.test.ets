import { assertHostForeground } from '../main/ets/core/HostLifecycleMonitor';
import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { getTestLifecycle, testAbility } from './TestHostLifecycle';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { APP_IN_BACKGROUND, HOST_LIFECYCLE_NOT_INITIALIZED } from '../main/ets/core/MiniAppErrorCode';
import { getTestUiAbilityContext } from './TestContext';

function stateError(context: common.UIAbilityContext): string {
  try {
    assertHostForeground(context);
    return '';
  } catch (error) {
    return (error as MiniAppError).code;
  }
}

export default function hostLifecycleMonitorTest(): void {
  describe('HostLifecycleMonitor', () => {
    it('requiresCreationAndTracksForegroundBackgroundAndDestroy', 0, () => {
      const context = getTestUiAbilityContext();
      getTestLifecycle().onAbilityDestroy(testAbility(context));
      expect(stateError(context)).assertEqual(HOST_LIFECYCLE_NOT_INITIALIZED);
      getTestLifecycle().onAbilityCreate(testAbility(context));
      expect(stateError(context)).assertEqual(APP_IN_BACKGROUND);
      getTestLifecycle().onAbilityForeground(testAbility(context));
      expect(stateError(context)).assertEqual('');
      getTestLifecycle().onAbilityBackground(testAbility(context));
      expect(stateError(context)).assertEqual(APP_IN_BACKGROUND);
      getTestLifecycle().onAbilityDestroy(testAbility(context));
      expect(stateError(context)).assertEqual(HOST_LIFECYCLE_NOT_INITIALIZED);
    });

    it('duplicateCreationPreservesStateAndLateNotificationsDoNotReviveDestroyedHost', 0, () => {
      const context = getTestUiAbilityContext();
      getTestLifecycle().onAbilityCreate(testAbility(context));
      getTestLifecycle().onAbilityForeground(testAbility(context));
      getTestLifecycle().onAbilityCreate(testAbility(context));
      expect(stateError(context)).assertEqual('');
      getTestLifecycle().onAbilityDestroy(testAbility(context));
      getTestLifecycle().onAbilityDestroy(testAbility(context));
      getTestLifecycle().onAbilityForeground(testAbility(context));
      getTestLifecycle().onAbilityBackground(testAbility(context));
      expect(stateError(context)).assertEqual(HOST_LIFECYCLE_NOT_INITIALIZED);
    });
  });
}
