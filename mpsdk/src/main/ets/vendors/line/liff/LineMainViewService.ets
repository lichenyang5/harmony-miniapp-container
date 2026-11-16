import { LineErrorCode } from '../LineErrorCode';
import { url } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineAccountManager } from '../auth/LineAccountManager';
import { LineSubViewCodec } from './LineSubViewCodec';
import { LineLiffViewResult } from './LineLiffTypes';

export class LineMainViewService {
  private sequence: number = 0;
  private readonly account: LineAccountManager;

  constructor(account: LineAccountManager) {
    this.account = account;
  }

  /** APK rf0/c.a：追加相对路径和查询，state 的 fragment 替换入口 fragment。 */
  private static mergeDirectLinkState(endpoint: url.URL, value: string): void {
    if (!value || value === '/') {
      return;
    }
    const pathless: boolean = value.startsWith('?') || value.startsWith('#');
    // 拼接固定 origin，避免把 //host 或绝对地址解释成导航目标。
    const state = new url.URL('https://liff-state.invalid' +
      (pathless || value.startsWith('/') ? '' : '/') + value);
    state.params.delete('liff.preferCachedInstance');
    const statePath: string = pathless ? '' : state.pathname;
    if ((statePath === '' || statePath === '/') && !state.search && !state.hash) {
      return;
    }
    if (statePath) {
      endpoint.pathname = endpoint.pathname +
        (endpoint.pathname.endsWith('/') && statePath.startsWith('/') ? statePath.substring(1) : statePath);
    }
    state.params.forEach((item: string, key: string): void => {
      endpoint.params.append(key, item);
    });
    endpoint.hash = state.hash;
  }

  /** 返回已合并直链状态和授权 fragment 的启动数据，不再向下游传递待处理的 launchOptions。 */
  async issue(liffId: string, requestedUrl: string, challenge: string): Promise<LineLiffViewResult> {
    let requested: url.URL;
    try {
      requested = new url.URL(requestedUrl);
      if (requested.protocol !== 'https:' || !requested.hostname || requested.username || requested.password) {
        throw new Error('invalid requested URL');
      }
    } catch (_) {
      throw new MiniAppError(LineErrorCode.MAINVIEW_INVALID, 'LINE 主视图请求地址无效');
    }
    const sequence: number = ++this.sequence;
    const body: Uint8Array = LineSubViewCodec.encodeMain(liffId, requestedUrl, requested.hostname, sequence);
    const result: LineLiffViewResult = LineSubViewCodec.decode(
      await this.account.sendLiffRpc('issueLiffView', body, liffId, sequence), sequence, 'issueLiffView');
    // APK 使用发行响应中的真实 LIFF ID；Mini App 别名与该 ID 可以不同。
    const issuedLiffId: string = result.liffId ?? liffId;
    if (!result.url || !result.accessToken || !result.featureToken || !result.contextToken || !issuedLiffId) {
      throw new MiniAppError(LineErrorCode.MAINVIEW_INVALID, 'LINE 主视图授权数据无效');
    }
    if (result.directLinkV1 === true && result.directLinkV2 !== true) {
      throw new MiniAppError(LineErrorCode.MAINVIEW_DIRECT_LINK_V1_UNSUPPORTED, 'LINE 主视图需要 V1 直链初始化');
    }
    let endpoint: url.URL;
    try {
      endpoint = new url.URL(result.url);
      if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password) {
        throw new Error('invalid issued URL');
      }
    } catch (_) {
      throw new MiniAppError(LineErrorCode.MAINVIEW_INVALID, 'LINE 主视图入口地址无效');
    }
    requested.params.forEach((value: string, key: string): void => {
      if (key === 'liff.state' && result.directLinkV2 === true) {
        endpoint.params.delete(key);
        LineMainViewService.mergeDirectLinkState(endpoint, value);
        return;
      }
      if (key !== 'liff.domain' && key !== 'liff.referrer') {
        endpoint.params.set(key, value);
      }
    });
    const address: string = endpoint.toString();
    const separator: string = address.includes('#') ? '&' : '#';
    return {
      liffId: issuedLiffId,
      viewType: result.viewType,
      url: address + separator +
        `context_token=${result.contextToken}&access_token=${result.accessToken}` +
        `&feature_token=${result.featureToken}&id_token=${result.idToken ?? ''}` +
        `&client_id=${result.clientId ?? ''}&mst_challenge=${challenge}`,
      contextToken: result.contextToken,
      accessToken: result.accessToken,
      featureToken: result.featureToken,
      idToken: result.idToken,
      clientId: result.clientId,
      scopes: result.scopes?.slice()
    };
  }
}
