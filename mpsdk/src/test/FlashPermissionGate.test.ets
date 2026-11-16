import { describe, expect, it } from '@ohos/hypium';
import { PermissionRequestResult } from '@kit.AbilityKit';
import {
  CameraPermissionGateway,
  FlashPermissionGate,
  FlashPermissionProvider,
  parseCameraPermissionResult
} from '../main/ets/capabilities/flash/FlashPermissionGate';
import { FlashOperationCoordinator } from '../main/ets/capabilities/flash/FlashTools';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import {
  PERMISSION_DENIED, SYSTEM_ERROR, USER_CANCELLED
} from '../main/ets/core/MiniAppErrorCode';

class RecordingCameraPermissionGateway implements CameraPermissionGateway {
  granted: boolean = false;
  confirmResult: boolean = true;
  requestResult: boolean = true;
  deferConfirmation: boolean = false;
  events: string[] = [];
  private confirmResolver?: (allowed: boolean) => void;

  hasPermission(): boolean {
    this.events.push('check');
    return this.granted;
  }

  confirmAccess(): Promise<boolean> {
    this.events.push('confirm');
    if (!this.deferConfirmation) {
      return Promise.resolve(this.confirmResult);
    }
    return new Promise<boolean>((resolve: (allowed: boolean) => void): void => {
      this.confirmResolver = resolve;
    });
  }

  requestPermission(): Promise<boolean> {
    this.events.push('request');
    return Promise.resolve(this.requestResult);
  }

  completeConfirmation(allowed: boolean): void {
    this.confirmResolver?.(allowed);
    this.confirmResolver = undefined;
  }
}

class DeferredFlashPermissionProvider implements FlashPermissionProvider {
  private resolver?: () => void;

  ensureAllowed(enabled: boolean): Promise<void> {
    if (!enabled) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void): void => {
      this.resolver = resolve;
    });
  }

  complete(): void {
    this.resolver?.();
    this.resolver = undefined;
  }
}

export default function flashPermissionGateTest(): void {
  describe('FlashPermissionGate', () => {
    it('skipsPermissionFlowWhenTurningFlashOff', 0, async () => {
      const gateway: RecordingCameraPermissionGateway = new RecordingCameraPermissionGateway();
      const gate: FlashPermissionGate = new FlashPermissionGate(gateway);

      await gate.ensureAllowed(false);

      expect(gateway.events.length).assertEqual(0);
    });

    it('skipsDialogsWhenCameraPermissionIsAlreadyGranted', 0, async () => {
      const gateway: RecordingCameraPermissionGateway = new RecordingCameraPermissionGateway();
      gateway.granted = true;
      const gate: FlashPermissionGate = new FlashPermissionGate(gateway);

      await gate.ensureAllowed(true);

      expect(JSON.stringify(gateway.events)).assertEqual('["check"]');
    });

    it('stopsBeforeSystemDialogWhenSdkConfirmationIsDenied', 0, async () => {
      const gateway: RecordingCameraPermissionGateway = new RecordingCameraPermissionGateway();
      gateway.confirmResult = false;
      const gate: FlashPermissionGate = new FlashPermissionGate(gateway);
      let errorCode: string = '';

      try {
        await gate.ensureAllowed(true);
      } catch (error) {
        errorCode = (error as MiniAppError).code;
      }

      expect(errorCode).assertEqual(USER_CANCELLED);
      expect(JSON.stringify(gateway.events)).assertEqual('["check","confirm"]');
    });

    it('reportsPermissionDeniedWhenSystemRequestIsDenied', 0, async () => {
      const gateway: RecordingCameraPermissionGateway = new RecordingCameraPermissionGateway();
      gateway.requestResult = false;
      const gate: FlashPermissionGate = new FlashPermissionGate(gateway);
      let errorCode: string = '';

      try {
        await gate.ensureAllowed(true);
      } catch (error) {
        errorCode = (error as MiniAppError).code;
      }

      expect(errorCode).assertEqual(PERMISSION_DENIED);
      expect(JSON.stringify(gateway.events)).assertEqual('["check","confirm","request"]');
    });

    it('allowsFlashAfterBothPermissionStepsSucceed', 0, async () => {
      const gateway: RecordingCameraPermissionGateway = new RecordingCameraPermissionGateway();
      const gate: FlashPermissionGate = new FlashPermissionGate(gateway);

      await gate.ensureAllowed(true);

      expect(JSON.stringify(gateway.events)).assertEqual('["check","confirm","request"]');
    });

    it('sharesOnePermissionFlowAcrossConcurrentEnableRequests', 0, async () => {
      const gateway: RecordingCameraPermissionGateway = new RecordingCameraPermissionGateway();
      gateway.deferConfirmation = true;
      const gate: FlashPermissionGate = new FlashPermissionGate(gateway);

      const first: Promise<void> = gate.ensureAllowed(true);
      const second: Promise<void> = gate.ensureAllowed(true);

      expect(JSON.stringify(gateway.events)).assertEqual('["check","confirm"]');
      gateway.completeConfirmation(true);
      await first;
      await second;
      expect(JSON.stringify(gateway.events)).assertEqual('["check","confirm","request"]');
    });

    it('clearsRejectedPermissionFlowSoTheUserCanRetry', 0, async () => {
      const gateway: RecordingCameraPermissionGateway = new RecordingCameraPermissionGateway();
      gateway.confirmResult = false;
      const gate: FlashPermissionGate = new FlashPermissionGate(gateway);

      try {
        await gate.ensureAllowed(true);
      } catch (_) {
      }
      gateway.confirmResult = true;
      await gate.ensureAllowed(true);

      expect(JSON.stringify(gateway.events)).assertEqual(
        '["check","confirm","check","confirm","request"]');
    });

    it('rejectsInvalidHarmonyPermissionResultsAsSystemErrors', 0, () => {
      const result: PermissionRequestResult = {
        permissions: ['ohos.permission.CAMERA'],
        authResults: [2]
      };
      let errorCode: string = '';

      try {
        parseCameraPermissionResult(result);
      } catch (error) {
        errorCode = (error as MiniAppError).code;
      }

      expect(errorCode).assertEqual(SYSTEM_ERROR);
    });
  });

  describe('FlashOperationCoordinator', () => {
    it('doesNotApplyAnOlderEnableAfterANewerDisable', 0, async () => {
      const permissionProvider: DeferredFlashPermissionProvider =
        new DeferredFlashPermissionProvider();
      const coordinator: FlashOperationCoordinator =
        new FlashOperationCoordinator(permissionProvider);
      const applied: boolean[] = [];
      const apply = (enabled: boolean): void => {
        applied.push(enabled);
      };

      const enabling: Promise<void> = coordinator.run(true, apply);
      await coordinator.run(false, apply);
      permissionProvider.complete();
      await enabling;

      expect(JSON.stringify(applied)).assertEqual('[false]');
    });
  });
}
