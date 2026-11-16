import { url } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { INVALID_ARGUMENT } from '../../../core/MiniAppErrorCode';
import { LINE_LIFF_HOST, LINE_MINIAPP_HOST } from '../scheme/LineSchemeConstants';

export interface LineLiffUrlTarget {
  appId: string;
  url: string;
}

/** 调用方先校验浏览器地址；状态以原编码包装，避免路径规范化或 fragment 丢失。 */
export function resolveLineLiffUrl(address: string, parsed: url.URL): LineLiffUrlTarget | undefined {
  try {
    if (parsed.protocol !== 'https:' ||
      (parsed.hostname !== LINE_LIFF_HOST && parsed.hostname !== LINE_MINIAPP_HOST)) {
      return undefined;
    }
    // URL.pathname 会规范化点路径；包装 state 时使用原始编码，避免丢失目标状态。
    const raw: RegExpMatchArray | null = address.match(/^[a-z][a-z0-9+.-]*:\/\/[^/?#\\]+(.*)$/i);
    const tail: string = raw?.[1] ?? '';
    const path: string = tail.split(/[?#]/)[0];
    const segment: RegExpMatchArray | null = path.match(/^\/+([^/]+)/);
    const firstSegment: string = segment?.[1] ?? '';
    if (!firstSegment) {
      return undefined;
    }
    // 业务 ID 与 Android getPathSegments 一致解码；URL 仍保留原始段，编码斜线不进入 URL 结构。
    const appId: string = decodeURIComponent(firstSegment);
    let state: string = tail.substring(segment?.[0].length ?? 0);
    // APK rf0/c.i：只去掉独立的 /，或开头 /?、/# 中的 /；其余内容整体包装。
    if (state === '/' || state.startsWith('/?') || state.startsWith('/#')) {
      state = state.substring(1);
    }
    const target: string = parsed.origin + '/' + firstSegment;
    return {
      appId,
      url: target + (state ? '?liff.state=' + encodeURIComponent(state) : '')
    };
  } catch (error) {
    throw MiniAppError.from(error as Object, INVALID_ARGUMENT, 'Invalid LIFF URL');
  }
}
