import { VendorAdapter } from '../main/ets/core/VendorAdapter';
import { TestVendorAdapter } from './TestVendorAdapter';
import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { NOT_SUPPORTED, SESSION_CLOSED, SYSTEM_ERROR } from '../main/ets/core/MiniAppErrorCode';
import {
  BridgeInjection,
  DocumentScript,
  MiniAppDescriptor,
  MiniAppSession,
  SwipeBackController,
  Vendor,
  VendorBinding
} from '../main/ets/core/Runtime';
import { getTestUiAbilityContext } from './TestContext';

class SwipeNoopVendorBinding implements VendorBinding {
  injections: BridgeInjection[] = [];
  scripts: DocumentScript[] = [];

  onDocumentChanged(_documentId: number): void {
  }

  dispose(): void {
  }
}

class SwipeNoopVendor implements Vendor {
  readonly vendorId: string = 'swipe-runtime-test';

  createDefaultAdapter(): VendorAdapter {
    return new TestVendorAdapter(this.vendorId);
  }

  createBinding(_session: MiniAppSession): VendorBinding {
    return new SwipeNoopVendorBinding();
  }
}

class RecordingSwipeBackController implements SwipeBackController {
  settings: boolean[] = [];
  disposed: boolean = false;
  failApply: boolean = false;
  failure?: MiniAppError;

  setEnabled(enabled: boolean): void {
    if (this.failure) {
      throw this.failure;
    }
    if (this.failApply) {
      throw new Error('native failure');
    }
    this.settings.push(enabled);
  }

  dispose(): void {
    this.disposed = true;
  }
}

function createSwipeSession(id: string, swipeBackController: SwipeBackController): MiniAppSession {
  const descriptor: MiniAppDescriptor = {
    info: { appId: id, vendor: 'swipe-runtime-test', url: 'https://example.com/' + id },
    vendor: new SwipeNoopVendor(),
    adapter: new TestVendorAdapter('swipe-runtime-test'),
    swipeBackController
  };
  return new MiniAppSession(id, descriptor, getTestUiAbilityContext() as common.UIAbilityContext);
}

export default function swipeSettingsRuntimeTest(): void {
  describe('SwipeSettingsRuntime', () => {
    it('forwardsSettingsOnlyToOwningSession', 0, () => {
      const firstController: RecordingSwipeBackController = new RecordingSwipeBackController();
      const secondController: RecordingSwipeBackController = new RecordingSwipeBackController();
      const first: MiniAppSession = createSwipeSession('first-swipe', firstController);
      const second: MiniAppSession = createSwipeSession('second-swipe', secondController);

      first.setSwipeBackEnabled(false);
      second.setSwipeBackEnabled(true);

      expect(JSON.stringify(firstController.settings)).assertEqual('[false]');
      expect(JSON.stringify(secondController.settings)).assertEqual('[true]');
      first.close();
      second.close();
    });

    it('disposesNativeSwipeControllerWhenSessionCloses', 0, () => {
      const controller: RecordingSwipeBackController = new RecordingSwipeBackController();
      const session: MiniAppSession = createSwipeSession('restore-swipe', controller);

      session.setSwipeBackEnabled(false);
      session.close();

      expect(JSON.stringify(controller.settings)).assertEqual('[false]');
      expect(controller.disposed).assertTrue();
    });

    it('wrapsNativeSwipeFailuresAsSystemErrors', 0, () => {
      const controller: RecordingSwipeBackController = new RecordingSwipeBackController();
      controller.failApply = true;
      const session: MiniAppSession = createSwipeSession('failed-swipe', controller);
      let errorCode: string = '';

      try {
        session.setSwipeBackEnabled(false);
      } catch (error) {
        errorCode = (error as MiniAppError).code;
      }

      expect(errorCode).assertEqual(SYSTEM_ERROR);
      session.close();
    });

    it('preservesUnsupportedApiErrorsFromNativeController', 0, () => {
      const controller: RecordingSwipeBackController = new RecordingSwipeBackController();
      controller.failure = new MiniAppError(NOT_SUPPORTED, '当前系统版本不支持原生侧滑返回设置');
      const session: MiniAppSession = createSwipeSession('unsupported-swipe', controller);
      let errorCode: string = '';

      try {
        session.setSwipeBackEnabled(false);
      } catch (error) {
        errorCode = (error as MiniAppError).code;
      }

      expect(errorCode).assertEqual(NOT_SUPPORTED);
      session.close();
    });

    it('rejectsSwipeChangesAfterSessionClose', 0, () => {
      const controller: RecordingSwipeBackController = new RecordingSwipeBackController();
      const session: MiniAppSession = createSwipeSession('closed-swipe', controller);
      session.close();
      let errorCode: string = '';

      try {
        session.setSwipeBackEnabled(false);
      } catch (error) {
        errorCode = (error as MiniAppError).code;
      }

      expect(errorCode).assertEqual(SESSION_CLOSED);
      expect(controller.settings.length).assertEqual(0);
    });
  });
}
