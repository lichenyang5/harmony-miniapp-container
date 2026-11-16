import { scanCore } from '@kit.ScanKit';
import { BridgeContext } from '../../../../core/Runtime';
import { CodeReaderTools } from '../../../../capabilities/media/CodeReaderTools';
import { MiniAppError } from '../../../../core/MiniAppError';
import { NOT_SUPPORTED, USER_CANCELLED } from '../../../../core/MiniAppErrorCode';
import { LineBridgeError } from '../../LineBridgeError';
import { LINE_SCAN_CODE_V2_METHOD } from '../../LineConstants';
import { LineEventContext } from '../../LineEventContext';
import { LineEventHandler } from '../../LineEventHandler';

interface LineScanCodeV2Result {
  value: string;
}

/** WEB_HOOK 对官方 liff.scanCodeV2 的原生扩展实现。 */
export class ExtScanCodeV2Handler implements LineEventHandler<LineScanCodeV2Result> {
  readonly context: BridgeContext;
  readonly type: string = LINE_SCAN_CODE_V2_METHOD;
  readonly ext: boolean = true
  private readonly reader: CodeReaderTools;

  constructor(context: BridgeContext) {
    this.context = context;
    this.reader = new CodeReaderTools(context.uiAbilityContext);
  }

  async handle(_params: object, _request: LineEventContext): Promise<LineScanCodeV2Result> {
    try {
      const value: string = await this.reader.read(scanCore.ScanType.QR_CODE);
      return { value };
    } catch (error) {
      if (error instanceof MiniAppError && error.code === NOT_SUPPORTED) {
        throw LineBridgeError.forbidden('The scanCodeV2 API is not supported in this environment.');
      }
      const message: string = error instanceof MiniAppError && error.code === USER_CANCELLED ?
        'The scan was cancelled.' : 'Failed to scan the code.';
      throw LineBridgeError.unknown(message, error as Object);
    }
  }

  dispose(): void {
    this.reader.dispose();
  }
}
