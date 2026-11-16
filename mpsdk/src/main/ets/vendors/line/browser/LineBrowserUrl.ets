import { url } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { INVALID_ARGUMENT } from '../../../core/MiniAppErrorCode';

/** 打开入口与后续顶层导航使用相同策略；不接受本地文件、外部应用协议或内含凭据。 */
export function validateLineBrowserUrl(address: string): url.URL {
  try {
    if (typeof address !== 'string' || !/^https?:\/\/[^/?#\\]+/i.test(address) ||
      /[\u0000-\u0020\u007f]/.test(address)) {
      throw new MiniAppError(INVALID_ARGUMENT, 'Invalid browser URL');
    }
    const parsed: url.URL = new url.URL(address);
    if (!parsed.hostname || parsed.username || parsed.password) {
      throw new MiniAppError(INVALID_ARGUMENT, 'Unsupported browser URL');
    }
    return parsed;
  } catch (error) {
    throw MiniAppError.from(error as Object, INVALID_ARGUMENT, 'Invalid browser URL');
  }
}
