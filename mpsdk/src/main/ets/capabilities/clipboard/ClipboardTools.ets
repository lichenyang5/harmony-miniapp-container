import { pasteboard } from '@kit.BasicServicesKit';

/** 仅在用户主动选择复制后写入纯文本，不读取系统剪贴板。 */
export class ClipboardTools {
  static async writeText(text: string): Promise<void> {
    await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
  }
}
