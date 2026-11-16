import { url } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { MiniAppError } from '../../core/MiniAppError';
import { SdkLogger } from '../../logging/SdkLogger';
import { LineErrorCode } from './LineErrorCode';
import { LINE_MINIAPP_HOST } from './scheme/LineSchemeConstants';

const LINE_MINI_APP_ORIGIN: string = 'https://' + LINE_MINIAPP_HOST;
const RESOLVE_TIMEOUT_MS: number = 8000;
const MAX_LANDING_LENGTH: number = 131072;
const TAG: string = 'LineCustomPathResolver';

/** LINE 的公开入口页面会将 Custom Path 映射为客户端 LIFF 启动地址。页面格式并非公开 API。 */
export class LineCustomPathResolver {
  private static customPath(address: string): string | undefined {
    try {
      const target = new url.URL(address);
      if (target.origin !== LINE_MINI_APP_ORIGIN || target.username || target.password) return undefined;
      const match = target.pathname.match(/^\/([a-z0-9_]{3,28}[a-z0-9])(?:\/|$)/);
      if (!match || /^\d+$/.test(match[1])) return undefined;
      return match[1];
    } catch (_) {
      return undefined;
    }
  }

  static isCustomPathUrl(address: string): boolean {
    return LineCustomPathResolver.customPath(address) !== undefined;
  }

  /** 只请求官方域名下的别名根路径，不发送原地址的查询、片段或用户凭据。 */
  static async resolve(address: string): Promise<string> {
    const path = LineCustomPathResolver.customPath(address);
    if (!path) {
      throw new MiniAppError(LineErrorCode.CUSTOM_PATH_INVALID, 'LINE Custom Path 地址无效');
    }
    const client = http.createHttp();
    let redirected: boolean = false;
    let destroyed: boolean = false;
    const stop = (): void => {
      if (destroyed) return;
      destroyed = true;
      client.destroy();
    };
    const startedAt: number = Date.now();
    try {
      // 当前元服务 API 没有重定向开关；观察到 Location 时尽早中止，不接受已观察到的重定向正文。
      client.on('headersReceive', (headers: Object): void => {
        if (Object.keys(headers).some((key: string): boolean => key.toLowerCase() === 'location')) {
          redirected = true;
          stop();
        }
      });
      const response = await client.request(`${LINE_MINI_APP_ORIGIN}/${path}`, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: RESOLVE_TIMEOUT_MS,
        readTimeout: RESOLVE_TIMEOUT_MS,
        usingCache: false
      });
      if (redirected) {
        throw new MiniAppError(LineErrorCode.CUSTOM_PATH_RESOLVE_FAILED, 'LINE Custom Path 返回重定向');
      }
      if (response.responseCode === 404) {
        throw new MiniAppError(LineErrorCode.CUSTOM_PATH_NOT_FOUND, 'LINE Custom Path 不存在');
      }
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        throw new MiniAppError(LineErrorCode.CUSTOM_PATH_RESOLVE_FAILED, 'LINE Custom Path 请求失败');
      }
      if (response.result.length > MAX_LANDING_LENGTH) {
        throw new MiniAppError(LineErrorCode.CUSTOM_PATH_RESPONSE_INVALID, 'LINE Custom Path 页面格式无效');
      }
      const match = response.result.match(/\b(?:const|let)\s+liffUrlForLINEApp\s*=\s*["']line:\/\/app\/(\d+-[A-Za-z0-9]+)["']/);
      if (!match) {
        throw new MiniAppError(LineErrorCode.CUSTOM_PATH_RESPONSE_INVALID, 'LINE Custom Path 页面缺少 LIFF ID');
      }
      SdkLogger.info(TAG, 'resolved', { vendorId: 'line', durationMs: Date.now() - startedAt });
      return match[1];
    } catch (error) {
      const failure = MiniAppError.from(error, LineErrorCode.CUSTOM_PATH_RESOLVE_FAILED,
        'LINE Custom Path 请求失败');
      SdkLogger.warn(TAG, 'resolveFailed', { vendorId: 'line', code: failure.code,
        durationMs: Date.now() - startedAt });
      throw failure;
    } finally {
      stop();
    }
  }
}
