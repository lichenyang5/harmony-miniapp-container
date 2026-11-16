import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { assertHostForeground } from '../../core/HostLifecycleMonitor';
import { MiniAppError } from '../../core/MiniAppError';
import {
  CAPABILITY_BUSY,
  INVALID_CAPABILITY_RESULT,
  NOT_SUPPORTED,
  SESSION_CLOSED,
  SYSTEM_ERROR,
  USER_CANCELLED
} from '../../core/MiniAppErrorCode';

export type CodeScanInvoker = (context: common.Context,
  options: scanBarcode.ScanOptions) => Promise<scanBarcode.ScanResult>;

/** 使用系统扫码页；占用由原生调用结束释放，不随会话销毁提前释放。 */
export class CodeReaderTools {
  private static readonly activeContexts: Set<common.UIAbilityContext> = new Set<common.UIAbilityContext>();
  private readonly context: common.UIAbilityContext;
  private readonly invoke: CodeScanInvoker;
  private readonly supported: boolean;
  private disposed: boolean = false;

  constructor(context: common.UIAbilityContext, invoke?: CodeScanInvoker, supported?: boolean) {
    this.context = context;
    this.invoke =
      invoke ?? ((host: common.Context, options: scanBarcode.ScanOptions): Promise<scanBarcode.ScanResult> =>
      scanBarcode.startScanForResult(host, options));
    this.supported = supported ?? canIUse('SystemCapability.Multimedia.Scan.ScanBarcode');
  }

  async read(scanType: scanCore.ScanType = scanCore.ScanType.ALL): Promise<string> {
    this.assertOpen();
    if (!this.supported) {
      throw new MiniAppError(NOT_SUPPORTED, 'Code reader is not supported');
    }
    // 检查与启动之间不等待异步查询，也不从窗口显示状态推断前后台。
    assertHostForeground(this.context);
    if (CodeReaderTools.activeContexts.has(this.context)) {
      throw new MiniAppError(CAPABILITY_BUSY, 'Code reader is already open');
    }
    CodeReaderTools.activeContexts.add(this.context);
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanType], enableMultiMode: false, enableAlbum: true
      };
      let result: scanBarcode.ScanResult;
      try {
        result = await this.invoke(this.context, options);
      } catch (error) {
        this.assertOpen();
        if (error && (error as BusinessError).code === 1000500002) {
          throw new MiniAppError(USER_CANCELLED, 'Code reader cancelled', error);
        }
        throw new MiniAppError(SYSTEM_ERROR, 'Code reader failed', error);
      }
      this.assertOpen();
      if (!result || typeof result.originalValue !== 'string' || result.originalValue.length === 0) {
        throw new MiniAppError(INVALID_CAPABILITY_RESULT, 'Code reader returned an invalid result');
      }
      return result.originalValue;
    } finally {
      CodeReaderTools.activeContexts.delete(this.context);
    }
  }

  dispose(): void {
    this.disposed = true;
  }

  private assertOpen(): void {
    if (this.disposed) {
      throw new MiniAppError(SESSION_CLOSED, 'Code reader is closed');
    }
  }
}
