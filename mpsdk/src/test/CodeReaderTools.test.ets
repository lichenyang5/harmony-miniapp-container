import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { CodeReaderTools } from '../main/ets/capabilities/media/CodeReaderTools';
import { getTestLifecycle, testAbility } from './TestHostLifecycle';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import {
  APP_IN_BACKGROUND,
  CAPABILITY_BUSY,
  HOST_LIFECYCLE_NOT_INITIALIZED,
  INVALID_CAPABILITY_RESULT,
  NOT_SUPPORTED,
  SESSION_CLOSED,
  SYSTEM_ERROR,
  USER_CANCELLED
} from '../main/ets/core/MiniAppErrorCode';
import { getTestUiAbilityContext } from './TestContext';

class NativeScanError extends Error {
  code: number;

  constructor(code: number) {
    super('native private details');
    this.code = code;
  }
}

function foregroundContext(): common.UIAbilityContext {
  const context = getTestUiAbilityContext();
  getTestLifecycle().onAbilityCreate(testAbility(context));
  getTestLifecycle().onAbilityForeground(testAbility(context));
  return context;
}

function scanResult(value: string): scanBarcode.ScanResult {
  return { scanType: scanCore.ScanType.QR_CODE, originalValue: value };
}

async function errorCode(operation: Promise<string>): Promise<string> {
  try {
    await operation;
  } catch (error) {
    return (error as MiniAppError).code;
  }
  return '';
}

export default function codeReaderToolsTest(): void {
  describe('CodeReaderTools', () => {
    it('returnsRawTextAndUsesSystemSingleScanWithAlbum', 0, async () => {
      const context = foregroundContext();
      const tools = new CodeReaderTools(context, async (received: common.Context,
        options: scanBarcode.ScanOptions): Promise<scanBarcode.ScanResult> => {
        expect(received === context).assertTrue();
        expect(options.scanTypes?.[0]).assertEqual(scanCore.ScanType.ALL);
        expect(options.enableMultiMode).assertFalse();
        expect(options.enableAlbum).assertTrue();
        return scanResult(' https://example.com/?a=1&b=2 ');
      }, true);
      expect(await tools.read()).assertEqual(' https://example.com/?a=1&b=2 ');
      tools.dispose();
      getTestLifecycle().onAbilityDestroy(testAbility(context));
    });

    it('acceptsQrOnlyWithoutChangingTheDefaultScanType', 0, async () => {
      const context = foregroundContext();
      const scanTypes: scanCore.ScanType[] = [];
      const tools = new CodeReaderTools(context, async (_received: common.Context,
        options: scanBarcode.ScanOptions): Promise<scanBarcode.ScanResult> => {
        scanTypes.push(options.scanTypes![0]);
        return scanResult('qr');
      }, true);
      expect(await tools.read(scanCore.ScanType.QR_CODE)).assertEqual('qr');
      expect(await tools.read()).assertEqual('qr');
      expect(scanTypes[0]).assertEqual(scanCore.ScanType.QR_CODE);
      expect(scanTypes[1]).assertEqual(scanCore.ScanType.ALL);
      tools.dispose();
      getTestLifecycle().onAbilityDestroy(testAbility(context));
    });

    it('mapsCancelAndSystemFailureAndReleasesBusyState', 0, async () => {
      const context = foregroundContext();
      let code: number = 1000500002;
      const tools = new CodeReaderTools(context, async (): Promise<scanBarcode.ScanResult> => {
        throw new NativeScanError(code);
      }, true);
      expect(await errorCode(tools.read())).assertEqual(USER_CANCELLED);
      code = 1000500001;
      expect(await errorCode(tools.read())).assertEqual(SYSTEM_ERROR);
      tools.dispose();
      getTestLifecycle().onAbilityDestroy(testAbility(context));
    });

    it('rejectsUnsupportedAndInvalidResults', 0, async () => {
      const context = foregroundContext();
      let calls: number = 0;
      const invoke = async (): Promise<scanBarcode.ScanResult> => {
        calls++;
        return scanResult('');
      };
      const unsupported = new CodeReaderTools(context, invoke, false);
      expect(await errorCode(unsupported.read())).assertEqual(NOT_SUPPORTED);
      expect(calls).assertEqual(0);
      const tools = new CodeReaderTools(context, invoke, true);
      expect(await errorCode(tools.read())).assertEqual(INVALID_CAPABILITY_RESULT);
      unsupported.dispose();
      tools.dispose();
      getTestLifecycle().onAbilityDestroy(testAbility(context));
    });

    it('keepsContextOccupiedUntilNativeScannerFinishesEvenAfterDispose', 0, async () => {
      const context = foregroundContext();
      let finish: (result: scanBarcode.ScanResult) => void = (_result: scanBarcode.ScanResult): void => {
      };
      const first = new CodeReaderTools(context, (): Promise<scanBarcode.ScanResult> => {
        return new Promise<scanBarcode.ScanResult>((resolve) => {
          finish = resolve;
        });
      }, true);
      const second =
        new CodeReaderTools(context, async (): Promise<scanBarcode.ScanResult> => scanResult('second'), true);
      const pending = errorCode(first.read());
      expect(await errorCode(first.read())).assertEqual(CAPABILITY_BUSY);
      first.dispose();
      expect(await errorCode(second.read())).assertEqual(CAPABILITY_BUSY);
      finish(scanResult('old'));
      expect(await pending).assertEqual(SESSION_CLOSED);
      expect(await second.read()).assertEqual('second');
      expect(await errorCode(first.read())).assertEqual(SESSION_CLOSED);
      second.dispose();
      getTestLifecycle().onAbilityDestroy(testAbility(context));
    });

    it('rejectsBackgroundWithoutScanningAndAllowsForegroundRetry', 0, async () => {
      const context = foregroundContext();
      getTestLifecycle().onAbilityBackground(testAbility(context));
      let calls: number = 0;
      const tools = new CodeReaderTools(context, async (): Promise<scanBarcode.ScanResult> => {
        calls++;
        return scanResult('retry');
      }, true);
      expect(await errorCode(tools.read())).assertEqual(APP_IN_BACKGROUND);
      expect(calls).assertEqual(0);
      getTestLifecycle().onAbilityForeground(testAbility(context));
      expect(await tools.read()).assertEqual('retry');
      expect(calls).assertEqual(1);
      tools.dispose();
      getTestLifecycle().onAbilityDestroy(testAbility(context));
    });

    it('doesNotStartScannerWithoutHostLifecycleOrAfterDestroy', 0, async () => {
      const context = getTestUiAbilityContext();
      getTestLifecycle().onAbilityDestroy(testAbility(context));
      let calls: number = 0;
      const tools = new CodeReaderTools(context, async (): Promise<scanBarcode.ScanResult> => {
        calls++;
        return scanResult('late');
      }, true);
      expect(await errorCode(tools.read())).assertEqual(HOST_LIFECYCLE_NOT_INITIALIZED);
      getTestLifecycle().onAbilityCreate(testAbility(context));
      getTestLifecycle().onAbilityForeground(testAbility(context));
      getTestLifecycle().onAbilityDestroy(testAbility(context));
      expect(await errorCode(tools.read())).assertEqual(HOST_LIFECYCLE_NOT_INITIALIZED);
      tools.dispose();
      expect(await errorCode(tools.read())).assertEqual(SESSION_CLOSED);
      expect(calls).assertEqual(0);
    });
  });
}
