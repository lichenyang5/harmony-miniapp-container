import { url } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineErrorCode } from '../LineErrorCode';

/** 仅允许已鉴权服务返回的 HTTPS 地址；这里不把第三方回跳限制为 access 域。 */
export function validateLineWebLoginReturn(address: string): string {
  try {
    const parsed = new url.URL(address);
    if (parsed.protocol === 'https:' && parsed.hostname && !parsed.username && !parsed.password) {
      return address;
    }
  } catch (_) {
  }
  throw new MiniAppError(LineErrorCode.WEB_LOGIN_PROTOCOL_INVALID, 'Invalid LINE web login return URL');
}

/** 仅替换该原生步骤拥有的参数，不重编码网站原有 query、PKCE 或 fragment。 */
export function setLineWebLoginParameters(address: string, values: Record<string, string>): string {
  const hashAt: number = address.indexOf('#');
  const fragment: string = hashAt < 0 ? '' : address.substring(hashAt);
  const base: string = hashAt < 0 ? address : address.substring(0, hashAt);
  const queryAt: number = base.indexOf('?');
  const path: string = queryAt < 0 ? base : base.substring(0, queryAt);
  const items: string[] = queryAt < 0 ? [] : base.substring(queryAt + 1).split('&');
  const keys = Object.keys(values);
  const retained = items.filter((item: string): boolean => {
    try {
      return keys.indexOf(decodeURIComponent(item.split('=')[0].replace(/\+/g, ' '))) < 0;
    } catch (_) {
      return true;
    }
  });
  keys.forEach((key: string): void => {
    retained.push(`${encodeURIComponent(key)}=${encodeURIComponent(values[key])}`);
  });
  return `${path}?${retained.join('&')}${fragment}`;
}
