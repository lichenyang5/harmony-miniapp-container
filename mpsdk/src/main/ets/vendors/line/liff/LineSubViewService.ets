import { LineLiffRpcMethod, LineRpcPath } from '../network/LineRpcConstants';
import { LineErrorCode } from '../LineErrorCode';
import { url } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import {
  LineHost,
  LineLiffViewResult,
  LineRpcRequest,
  LineSubViewRequest,
  LineSubWindowResultRequest
} from './LineLiffTypes';
import { LineSubViewCodec } from './LineSubViewCodec';

export class LineSubViewService {
  private sequence: number = 0;
  private readonly host?: LineHost;

  constructor(host?: LineHost) {
    this.host = host;
  }

  async storeResult(request: LineSubWindowResultRequest): Promise<void> {
    const sequence: number = ++this.sequence;
    const body: Uint8Array = LineSubViewCodec.encodeStoreResult(request, sequence);
    let response: Uint8Array;
    if (this.host?.account) {
      response = await this.host.account.sendLiffRpc(LineLiffRpcMethod.STORE_SUB_WINDOW_RESULT,
        body, request.liffId, sequence);
    } else if (this.host?.sendLiffRpc) {
      const rpc: LineRpcRequest = {
        method: LineLiffRpcMethod.STORE_SUB_WINDOW_RESULT,
        path: LineRpcPath.LIFF,
        liffId: request.liffId,
        body
      };
      response = await this.host.sendLiffRpc(rpc);
    } else {
      throw new MiniAppError(LineErrorCode.ACCOUNT_PROVIDER_REQUIRED, '请配置 LINE 子窗口结果传输来源');
    }
    LineSubViewCodec.decodeStoreResult(response, sequence);
  }

  async issue(request: LineSubViewRequest): Promise<LineLiffViewResult> {
    let result: LineLiffViewResult;
    try {
      if (this.host?.account) {
        const sequence: number = ++this.sequence;
        result = LineSubViewCodec.decode(await this.host.account.sendLiffRpc(LineLiffRpcMethod.ISSUE_SUB_VIEW,
          LineSubViewCodec.encode(request, sequence), request.liffId, sequence), sequence);
      } else if (this.host?.issueSubLiffView) {
        result = await this.host.issueSubLiffView(request);
      } else if (this.host?.sendLiffRpc) {
        const sequence: number = ++this.sequence;
        const rpc: LineRpcRequest = {
          method: LineLiffRpcMethod.ISSUE_SUB_VIEW,
          path: LineRpcPath.LIFF,
          liffId: request.liffId,
          body: LineSubViewCodec.encode(request, sequence)
        };
        result = LineSubViewCodec.decode(await this.host.sendLiffRpc(rpc), sequence);
      } else {
        throw new MiniAppError(LineErrorCode.ACCOUNT_PROVIDER_REQUIRED, '请配置 LINE 子视图授权来源');
      }
      if (typeof result.url !== 'string' ||
        (result.liffId !== undefined && (typeof result.liffId !== 'string' || !result.liffId)) ||
        (result.viewType !== undefined && typeof result.viewType !== 'string') ||
        typeof result.accessToken !== 'string' || !result.accessToken ||
        typeof result.featureToken !== 'string' || !result.featureToken ||
        typeof result.contextToken !== 'string' || !result.contextToken ||
        (result.idToken !== undefined && typeof result.idToken !== 'string') ||
        (result.clientId !== undefined && typeof result.clientId !== 'string') ||
        (result.hideCloseButton !== undefined && typeof result.hideCloseButton !== 'boolean') ||
        (result.presentationType !== undefined && !Number.isInteger(result.presentationType)) ||
        (result.closeButtonPosition !== undefined && !Number.isInteger(result.closeButtonPosition)) ||
        (result.closeButtonLabel !== undefined && typeof result.closeButtonLabel !== 'string') ||
        (result.scopes !== undefined && (!Array.isArray(result.scopes) ||
          !result.scopes.every((scope: string): boolean => typeof scope === 'string')))) {
        throw new MiniAppError(LineErrorCode.SUBVIEW_INVALID, 'LINE 子视图授权字段无效');
      }
      const endpoint = new url.URL(result.url);
      if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password) {
        throw new MiniAppError(LineErrorCode.SUBVIEW_INVALID, 'LINE 子视图缺少有效地址或授权数据');
      }
      // 返回独立快照，宿主不得在子窗口加载期间修改授权上下文。
      return {
        liffId: result.liffId ?? request.liffId,
        viewType: result.viewType,
        url: result.url,
        accessToken: result.accessToken,
        featureToken: result.featureToken,
        contextToken: result.contextToken,
        idToken: result.idToken,
        clientId: result.clientId,
        scopes: result.scopes?.slice(),
        hideCloseButton: result.hideCloseButton,
        presentationType: result.presentationType,
        closeButtonPosition: result.closeButtonPosition,
        closeButtonLabel: result.closeButtonLabel
      };
    } catch (error) {
      throw MiniAppError.from(error as Object, LineErrorCode.SUBVIEW_FAILED, '申请 LINE 子视图失败');
    }
  }
}
