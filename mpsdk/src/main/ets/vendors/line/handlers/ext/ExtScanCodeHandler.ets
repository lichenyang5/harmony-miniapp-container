import { LINE_SCAN_CODE_METHOD } from '../../LineConstants';
import { LineScanCodeHandler } from '../LineScanCodeHandler';


/** 旧版 LIFF scanCode：只扫 QR，取消时省略 value，不执行扫码链接。 */
export class ExtScanCodeHandler extends LineScanCodeHandler {
  readonly ext: boolean = true;
  readonly type: string = LINE_SCAN_CODE_METHOD
}
