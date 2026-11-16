import { webview } from '@kit.ArkWeb';

/** LIFF 网页初始请求头；不是账号 RPC 的 X-Line-Access。 */
export const LINE_LIFF_TOKEN_HEADER: string = 'X-LINE-LIFF-TOKEN';

export function createLineLiffHeaders(accessToken?: string): webview.WebHeader[] {
  return accessToken ? [{ headerKey: LINE_LIFF_TOKEN_HEADER, headerValue: accessToken }] : [];
}
