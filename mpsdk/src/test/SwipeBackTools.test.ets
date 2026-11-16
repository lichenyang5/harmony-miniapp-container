import { describe, expect, it } from '@ohos/hypium';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { NOT_SUPPORTED, SYSTEM_ERROR } from '../main/ets/core/MiniAppErrorCode';
import { SwipeBackTools } from '../main/ets/capabilities/swipe/SwipeBackTools';

class RecordingSwipeBackNativeContext {
  applied: boolean[] = [];
  failNext: boolean = false;

  enableSwipeBack(enabled: boolean): void {
    if (this.failNext) {
      this.failNext = false;
      throw new Error('native swipe failure');
    }
    this.applied.push(enabled);
  }
}

function captureErrorCode(operation: () => void): string {
  try {
    operation();
  } catch (error) {
    return (error as MiniAppError).code;
  }
  return '';
}

export default function swipeBackToolsTest(): void {
  describe('SwipeBackTools', () => {
    it('appliesNativeSwipeOnSupportedApi', 0, () => {
      const nativeContext: RecordingSwipeBackNativeContext = new RecordingSwipeBackNativeContext();
      const tools: SwipeBackTools = new SwipeBackTools(nativeContext,
        (enabled: boolean): void => nativeContext.enableSwipeBack(enabled), 18);

      tools.setEnabled(false);

      expect(JSON.stringify(nativeContext.applied)).assertEqual('[false]');
      tools.dispose();
    });

    it('rejectsUnsupportedApiBeforeNativeCall', 0, () => {
      const nativeContext: RecordingSwipeBackNativeContext = new RecordingSwipeBackNativeContext();
      const tools: SwipeBackTools = new SwipeBackTools(nativeContext,
        (enabled: boolean): void => nativeContext.enableSwipeBack(enabled), 17);

      const errorCode: string = captureErrorCode((): void => tools.setEnabled(false));

      expect(errorCode).assertEqual(NOT_SUPPORTED);
      expect(nativeContext.applied.length).assertEqual(0);
      tools.dispose();
    });

    it('doesNotOverwriteActiveOwnerWhenOlderSessionDisposes', 0, () => {
      const nativeContext: RecordingSwipeBackNativeContext = new RecordingSwipeBackNativeContext();
      const apply = (enabled: boolean): void => nativeContext.enableSwipeBack(enabled);
      const first: SwipeBackTools = new SwipeBackTools(nativeContext, apply, 18);
      const second: SwipeBackTools = new SwipeBackTools(nativeContext, apply, 18);

      first.setEnabled(false);
      second.setEnabled(true);
      first.dispose();

      expect(JSON.stringify(nativeContext.applied)).assertEqual('[false,true]');
      second.dispose();
      expect(JSON.stringify(nativeContext.applied)).assertEqual('[false,true,true]');
    });

    it('restoresPreviousOwnerBeforeRestoringDefault', 0, () => {
      const nativeContext: RecordingSwipeBackNativeContext = new RecordingSwipeBackNativeContext();
      const apply = (enabled: boolean): void => nativeContext.enableSwipeBack(enabled);
      const first: SwipeBackTools = new SwipeBackTools(nativeContext, apply, 18);
      const second: SwipeBackTools = new SwipeBackTools(nativeContext, apply, 18);

      first.setEnabled(false);
      second.setEnabled(true);
      second.dispose();

      expect(JSON.stringify(nativeContext.applied)).assertEqual('[false,true,false]');
      first.dispose();
      expect(JSON.stringify(nativeContext.applied)).assertEqual('[false,true,false,true]');
    });

    it('wrapsNativeApplyFailureAsSystemErrorWithoutTakingOwnership', 0, () => {
      const nativeContext: RecordingSwipeBackNativeContext = new RecordingSwipeBackNativeContext();
      const tools: SwipeBackTools = new SwipeBackTools(nativeContext,
        (enabled: boolean): void => nativeContext.enableSwipeBack(enabled), 18);
      nativeContext.failNext = true;

      const errorCode: string = captureErrorCode((): void => tools.setEnabled(false));

      expect(errorCode).assertEqual(SYSTEM_ERROR);
      tools.dispose();
      expect(nativeContext.applied.length).assertEqual(0);
    });
  });
}
