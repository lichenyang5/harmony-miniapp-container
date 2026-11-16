import { MiniAppError } from '../core/MiniAppError';
import { INVALID_ARGUMENT } from '../core/MiniAppErrorCode';
import { ParamAssert } from './ParamAssert';

/** 下载相对路径：允许目录分隔符，不允许绝对路径、路径穿越或非法文件名。 */
export class DownloadFileName {
  static segments(filename: string): string[] {
    ParamAssert.assertString(filename, 'filename', false);
    const parts = filename.replace(/\\/g, '/').split('/');
    for (const part of parts) {
      if (part.length === 0 || part.trim().length === 0 || part === '.' || part === '..' ||
        /[<>:"|?*\u0000-\u001f\u007f]/.test(part) || /[. ]$/.test(part)) {
        throw new MiniAppError(INVALID_ARGUMENT, 'Invalid download filename');
      }
    }
    return parts;
  }
}
