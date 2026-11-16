import { MiniAppInfo } from '../../../core/MiniAppOptions';
import { LINE_VENDOR_ID } from '../LineConstants';
import { LINE_APP_SCHEME, LINE_LIFF_APP_URL_PREFIX, LineLiffCommand } from './LineSchemeConstants';

/** 识别扫码结果中的小程序启动地址；保留 query/fragment 原编码，不重复包装 liff.state。 */
export function resolveLineAppSchemeUrl(address: string): MiniAppInfo | undefined {
  try {
    const route: RegExpMatchArray | null = address.match(
      new RegExp('^' + LINE_APP_SCHEME + '://([^/?#]*)([\\s\\S]*)$', 'i'));
    if (!route || route[1] !== LineLiffCommand.APP || /[\u0000-\u0020\u007f\\]/.test(address)) {
      return undefined;
    }
    const path: RegExpMatchArray | null = route[2].match(/^\/([^/?#]+)([?#].*)?$/);
    if (!path) {
      return undefined;
    }
    const appId: string = decodeURIComponent(path[1]);
    if (!appId || /[\s/?#\\\u0000-\u001f\u007f]/.test(appId)) {
      return undefined;
    }
    return { appId, vendor: LINE_VENDOR_ID, url: LINE_LIFF_APP_URL_PREFIX + path[1] + (path[2] ?? '') };
  } catch (_) {
    return undefined;
  }
}
