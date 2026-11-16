import { describe, expect, it } from '@ohos/hypium';
import { webview } from '@kit.ArkWeb';
import { MiniAppSession } from '../main/ets/core/Runtime';
import {
  MiniAppNavigationController,
  MiniAppNavigationEndpoint
} from '../main/ets/web/MiniAppNavigationController';

class RecordingNavigationEndpoint implements MiniAppNavigationEndpoint {
  homeCount: number = 0;
  refreshCount: number = 0;

  // 基类导航转发不应访问原生控制器或会话；意外访问时让测试明确失败。
  get controller(): webview.WebviewController {
    throw new Error('Base navigation must not access the WebviewController');
  }

  get session(): MiniAppSession {
    throw new Error('Base navigation must not access the MiniAppSession');
  }

  async navigateTo(_address: string): Promise<void> {
  }

  goHome(): void {
    this.homeCount++;
  }

  refresh(): void {
    this.refreshCount++;
  }
}

export default function miniAppNavigationControllerTest(): void {
  describe('MiniAppNavigationController', (): void => {
    it('baseOpenMenuIsNoop', 0, async (): Promise<void> => {
      const controller = new MiniAppNavigationController();
      const endpoint = new RecordingNavigationEndpoint();
      expect(await controller.openMenu()).assertFalse();
      controller.attach(endpoint);
      expect(await controller.openMenu()).assertFalse();
      controller.detach(endpoint);
      expect(await controller.openMenu()).assertFalse();
    });
    it('baseCloseMenuIsNoop', 0, async (): Promise<void> => {
      const controller = new MiniAppNavigationController();
      const endpoint = new RecordingNavigationEndpoint();
      expect(await controller.closeMenu()).assertFalse();
      controller.attach(endpoint);
      expect(await controller.closeMenu()).assertFalse();
      controller.detach(endpoint);
      expect(await controller.closeMenu()).assertFalse();
    });
    it('forwards home and refresh commands only while a view is attached', 0, (): void => {
      const controller = new MiniAppNavigationController();
      const endpoint = new RecordingNavigationEndpoint();

      controller.goHome();
      controller.refresh();
      controller.attach(endpoint);
      controller.goHome();
      controller.refresh();
      controller.detach(endpoint);
      controller.goHome();
      controller.refresh();

      expect(endpoint.homeCount).assertEqual(1);
      expect(endpoint.refreshCount).assertEqual(1);
    });

    it('does not let an old view detach a newer view', 0, (): void => {
      const controller = new MiniAppNavigationController();
      const oldEndpoint = new RecordingNavigationEndpoint();
      const currentEndpoint = new RecordingNavigationEndpoint();

      controller.attach(oldEndpoint);
      controller.attach(currentEndpoint);
      controller.detach(oldEndpoint);
      controller.refresh();

      expect(oldEndpoint.refreshCount).assertEqual(0);
      expect(currentEndpoint.refreshCount).assertEqual(1);
    });
  });
}
