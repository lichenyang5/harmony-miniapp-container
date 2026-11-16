import { http } from '@kit.NetworkKit';
import { url } from '@kit.ArkTS';
import { MiniAppError } from '../../core/MiniAppError';
import { LineErrorCode } from './LineErrorCode';

const MAX_HTML_BYTES: number = 1024 * 1024;
const RESOLVE_TIMEOUT_MS: number = 15000;
// 仅用于公开引导页请求，不覆盖 WebView UA，不携带账号或 LIFF 凭据。
const LANDING_USER_AGENT: string = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/** 每个 Binding 独立持有；只解析引导页的 JSON 字符串字面量，不执行远端脚本。 */
export class LineEntryResolver {
  private disposed: boolean = false;
  private client?: http.HttpRequest;
  private cancel?: () => void;

  async resolve(initialUrl: string, appId: string): Promise<string> {
    if (this.disposed) {
      throw new MiniAppError(LineErrorCode.SESSION_CLOSED, 'LINE 会话已关闭');
    }
    let entry: url.URL;
    try {
      entry = new url.URL(initialUrl);
    } catch (_) {
      throw new MiniAppError(LineErrorCode.ENTRY_INVALID, 'LINE 入口地址无效');
    }
    if (!this.isLandingHost(entry.hostname)) {
      return initialUrl;
    }
    try {
      if (entry.protocol !== 'https:' || entry.username || entry.password || entry.port ||
        decodeURIComponent(entry.pathname.split('/')[1]) !== appId) {
        throw new Error('invalid entry');
      }
    } catch (_) {
      throw new MiniAppError(LineErrorCode.ENTRY_INVALID, 'LINE 入口地址或应用标识无效');
    }
    if (this.client) {
      throw new MiniAppError(LineErrorCode.ENTRY_RESOLVE_FAILED, 'LINE 入口正在解析');
    }
    const fragment: string = entry.hash;
    entry.hash = '';
    let client: http.HttpRequest;
    try {
      client = http.createHttp();
    } catch (error) {
      throw MiniAppError.from(error as Object, LineErrorCode.ENTRY_RESOLVE_FAILED, 'LINE 入口请求创建失败');
    }
    this.client = client;
    let timer: number | undefined;
    try {
      const interrupted = new Promise<http.HttpResponse>((_resolve, reject): void => {
        this.cancel = (): void => {
          reject(new MiniAppError(LineErrorCode.SESSION_CLOSED, 'LINE 会话已关闭'));
        };
        timer = setTimeout((): void => {
          reject(new MiniAppError(LineErrorCode.ENTRY_RESOLVE_FAILED, 'LINE 入口解析超时'));
        }, RESOLVE_TIMEOUT_MS);
      });
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': LANDING_USER_AGENT, 'Accept': 'text/html' },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: RESOLVE_TIMEOUT_MS,
        maxLimit: MAX_HTML_BYTES,
        usingCache: false
      };
      const response: http.HttpResponse = await Promise.race([client.request(entry.toString(), options), interrupted]);
      if (this.disposed) {
        throw new MiniAppError(LineErrorCode.SESSION_CLOSED, 'LINE 会话已关闭');
      }
      if (response.responseCode !== 200 || typeof response.result !== 'string' ||
        response.result.length > MAX_HTML_BYTES) {
        throw new MiniAppError(LineErrorCode.ENTRY_RESOLVE_FAILED, 'LINE 引导页请求失败');
      }
      return this.parse(response.result, appId, fragment);
    } catch (error) {
      throw MiniAppError.from(error as Object, LineErrorCode.ENTRY_RESOLVE_FAILED, 'LINE 入口解析失败');
    } finally {
      if (timer !== undefined) clearTimeout(timer);
      this.cancel = undefined;
      if (this.client === client) {
        this.client = undefined;
        client.destroy();
      }
    }
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.cancel?.();
    this.cancel = undefined;
    const client = this.client;
    this.client = undefined;
    client?.destroy();
  }

  private parse(html: string, appId: string, fragment: string): string {
    try {
      // 只接受唯一、双引号 JSON 字符串；表达式、模板字面量和格式变化均明确失败。
      const targets: RegExpMatchArray | null = html.match(
        /\b(?:let|const|var)\s+liffFullUrlForBrowser\s*=\s*"(?:[^"\\\r\n]|\\.)*"(?=\s*(?:;|liffFullUrlForBrowser\s*=|window\.liffInfo\s*=|<\/script>|$))/g);
      const ids: RegExpMatchArray | null = html.match(
        /\bliffId\s*:\s*"(?:[^"\\\r\n]|\\.)*"(?=\s*[,}])/g);
      if (!targets || targets.length !== 1 || !ids || ids.length !== 1) {
        throw new Error('missing or ambiguous landing configuration');
      }
      const literal: string = targets[0].substring(targets[0].indexOf('=') + 1).trim().replace(/;$/, '');
      const target: string = JSON.parse(literal);
      const id: string = JSON.parse(ids[0].substring(ids[0].indexOf(':') + 1).trim());
      const endpoint = new url.URL(target);
      if (id !== appId || endpoint.protocol !== 'https:' || !endpoint.hostname ||
        endpoint.username || endpoint.password || this.isLandingHost(endpoint.hostname)) {
        throw new Error('invalid landing target');
      }
      if (fragment) {
        // 对齐引导页 buildLiffFullUrl：hash 属于启动 state，不覆盖业务 Endpoint 的 fragment。
        const state: string = endpoint.params.get('liff.state') ?? '';
        endpoint.params.set('liff.state', state + fragment);
      }
      return endpoint.toString();
    } catch (_) {
      throw new MiniAppError(LineErrorCode.ENTRY_INVALID, 'LINE 引导页入口配置无效');
    }
  }

  private isLandingHost(hostname: string): boolean {
    return hostname === 'miniapp.line.me' || hostname === 'liff.line.me';
  }
}
