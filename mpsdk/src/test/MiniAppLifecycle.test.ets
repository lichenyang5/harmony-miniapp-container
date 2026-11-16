import { describe, expect, it } from '@ohos/hypium';
import { MiniAppLifecycleChange, MiniAppLifecycleState } from '../main/ets/core/lifecycle/MiniAppLifecycle';
import {
  bindMiniAppLifecycle,
  MiniAppLifecycleController
} from '../main/ets/core/lifecycle/MiniAppLifecycleController';

export default function miniAppLifecycleTest(): void {
  describe('MiniAppLifecycle', (): void => {
    it('initially inactive container attaches directly in background', 0, (): void => {
      const controller = new MiniAppLifecycleController(false);
      const lifecycle = bindMiniAppLifecycle(controller);
      const changes: MiniAppLifecycleChange[] = [];
      controller.observe((change: MiniAppLifecycleChange): void => {
        changes.push(change);
      });

      expect(controller.getState()).assertEqual(MiniAppLifecycleState.CREATED);
      lifecycle.setHostForeground(true);
      expect(changes.length).assertEqual(0);
      lifecycle.setAttached();
      expect(controller.getState()).assertEqual(MiniAppLifecycleState.BACKGROUND);
      expect(controller.isForeground()).assertFalse();
      expect(changes.length).assertEqual(1);
      expect(changes[0].previous).assertEqual(MiniAppLifecycleState.CREATED);
      expect(changes[0].current).assertEqual(MiniAppLifecycleState.BACKGROUND);

      controller.activate();
      expect(controller.isForeground()).assertTrue();
      expect(changes.length).assertEqual(2);
      expect(changes[1].previous).assertEqual(MiniAppLifecycleState.BACKGROUND);
      expect(changes[1].current).assertEqual(MiniAppLifecycleState.FOREGROUND);
      lifecycle.destroy();
    });

    it('activation cannot override host background and destruction is terminal', 0, (): void => {
      const controller = new MiniAppLifecycleController();
      const lifecycle = bindMiniAppLifecycle(controller);
      const changes: MiniAppLifecycleChange[] = [];
      controller.observe((change: MiniAppLifecycleChange): void => {
        changes.push(change);
      });
      lifecycle.setHostForeground(true);
      lifecycle.setAttached();
      expect(controller.isForeground()).assertTrue();

      lifecycle.setHostForeground(false);
      controller.deactivate();
      controller.activate();
      expect(controller.getState()).assertEqual(MiniAppLifecycleState.BACKGROUND);
      expect(changes.length).assertEqual(2);
      lifecycle.destroy();
      expect(controller.getState()).assertEqual(MiniAppLifecycleState.DESTROYED);
      expect(changes.length).assertEqual(3);
      expect(changes[2].previous).assertEqual(MiniAppLifecycleState.BACKGROUND);
      expect(changes[2].current).assertEqual(MiniAppLifecycleState.DESTROYED);

      lifecycle.setHostForeground(true);
      lifecycle.setAttached();
      controller.activate();
      controller.deactivate();
      lifecycle.destroy();
      expect(controller.getState()).assertEqual(MiniAppLifecycleState.DESTROYED);
      expect(controller.isForeground()).assertFalse();
      expect(changes.length).assertEqual(3);
    });

    it('separate instances remain independent under the same host state', 0, (): void => {
      const first = new MiniAppLifecycleController();
      const second = new MiniAppLifecycleController();
      const firstLifecycle = bindMiniAppLifecycle(first);
      const secondLifecycle = bindMiniAppLifecycle(second);
      firstLifecycle.setHostForeground(true);
      secondLifecycle.setHostForeground(true);
      firstLifecycle.setAttached();
      secondLifecycle.setAttached();

      first.deactivate();
      expect(first.getState()).assertEqual(MiniAppLifecycleState.BACKGROUND);
      expect(second.isForeground()).assertTrue();
      firstLifecycle.destroy();
      expect(first.getState()).assertEqual(MiniAppLifecycleState.DESTROYED);
      expect(second.isForeground()).assertTrue();
      secondLifecycle.destroy();
    });

    it('unsubscribe is idempotent and preserves other observers', 0, (): void => {
      const controller = new MiniAppLifecycleController();
      const lifecycle = bindMiniAppLifecycle(controller);
      const removed: MiniAppLifecycleChange[] = [];
      const remaining: MiniAppLifecycleChange[] = [];
      const unsubscribe = controller.observe((change: MiniAppLifecycleChange): void => {
        removed.push(change);
      });
      controller.observe((change: MiniAppLifecycleChange): void => {
        remaining.push(change);
      });

      lifecycle.setAttached();
      expect(removed.length).assertEqual(1);
      expect(remaining.length).assertEqual(1);
      unsubscribe();
      unsubscribe();
      lifecycle.setHostForeground(true);
      lifecycle.destroy();
      expect(removed.length).assertEqual(1);
      expect(remaining.length).assertEqual(3);
      expect(remaining[2].current).assertEqual(MiniAppLifecycleState.DESTROYED);
    });
  });
}
