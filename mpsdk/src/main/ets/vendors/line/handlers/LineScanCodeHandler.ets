import { scanCore } from '@kit.ScanKit';
import { BridgeContext } from '../../../core/Runtime';
import { CodeReaderTools } from '../../../capabilities/media/CodeReaderTools';
import { MiniAppError } from '../../../core/MiniAppError';
import { SYSTEM_ERROR, USER_CANCELLED } from '../../../core/MiniAppErrorCode';
import { LINE_SCAN_CODE_METHOD } from '../LineConstants';
import { LineEventContext } from '../LineEventContext';
import { LineEventHandler } from '../LineEventHandler';

interface LineScanCodeResult {
  value?: string;
}

/** 旧版 LIFF scanCode：只扫 QR，取消时省略 value，不执行扫码链接。 */
export class LineScanCodeHandler implements LineEventHandler<LineScanCodeResult> {
  readonly context: BridgeContext;
  readonly type: string = LINE_SCAN_CODE_METHOD;
  private readonly reader: CodeReaderTools;
  readonly ext: boolean = false

  constructor(context: BridgeContext) {
    this.context = context;
    this.reader = new CodeReaderTools(context.uiAbilityContext);
  }

  async handle(_params: object, _request: LineEventContext): Promise<LineScanCodeResult> {
    try {
      const value: string = await this.reader.read(scanCore.ScanType.QR_CODE);
      return { value };
    } catch (error) {
      if (error instanceof MiniAppError && error.code === USER_CANCELLED) {
        return {};
      }
      // 其他错误由桥层统一脱敏，不能伪装成用户取消。
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, 'Code reader failed');
    }
  }

  dispose(): void {
    this.reader.dispose();
  }
}
