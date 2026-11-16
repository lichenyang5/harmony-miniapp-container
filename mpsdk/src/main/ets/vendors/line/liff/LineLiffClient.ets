import { LineLiffRpcMethod, LineRpcPath } from '../network/LineRpcConstants';
import { LineErrorCode } from '../LineErrorCode';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineTransportRequest } from '../network/LineTransport';
import { LineSubViewCodec } from './LineSubViewCodec';
import { SdkLogger } from '../../../logging/SdkLogger';

/** 内部账号访问面，LIFF 不读取存储、不持有可变凭据，也不拥有账号生命周期。 */
export interface LineLiffAccount {
  getVersion(): number;

  requireAccessToken(): string;

  sendAccountRpc(request: LineTransportRequest): Promise<Uint8Array>;

  refreshRejectedToken(previousToken: string, generation: number): Promise<void>;
}

export class LineLiffClient {
  private readonly account: LineLiffAccount;

  constructor(account: LineLiffAccount) {
    this.account = account;
  }

  async send(method: string, body: Uint8Array, liffId: string, sequence?: number,
    checkResponse?: (bytes: Uint8Array) => void): Promise<Uint8Array> {
    const generation: number = this.account.getVersion();
    const token: string = this.account.requireAccessToken();
    const request: LineTransportRequest = {
      path: LineRpcPath.LIFF,
      method,
      body,
      liffId
    };
    const response = await this.sendRequest(request);
    if (sequence === undefined) {
      return response;
    }
    try {
      if (checkResponse) {
        checkResponse(response);
      } else if (method === LineLiffRpcMethod.STORE_SUB_WINDOW_RESULT) {
        LineSubViewCodec.decodeStoreResult(response, sequence);
      } else {
        LineSubViewCodec.decode(response, sequence, method);
      }
      return response;
    } catch (error) {
      if (!(error instanceof MiniAppError) || error.code !== LineErrorCode.ACCOUNT_MUST_REFRESH) {
        throw MiniAppError.from(error as Object, LineErrorCode.LIFF_FAILED, 'LINE 小程序请求失败');
      }
    }
    // 只重试一次；第二次响应由调用服务解码，避免刷新与 LIFF 请求形成无限循环。
    // 刷新传入原账号代次，退出或切换账号后不得将请求续接到新账号。
    await this.account.refreshRejectedToken(token, generation);
    if (this.account.getVersion() !== generation) {
      throw new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE 账号已切换或退出');
    }
    return this.sendRequest(request);
  }

  /** 与登录 RPC 共用私有 Debug 输出规则；刷新后的重试也记录实际收发数据。 */
  private async sendRequest(request: LineTransportRequest): Promise<Uint8Array> {
    SdkLogger.debug('LineLiff', `${request.method}Request`, {
      data: JSON.stringify({ liffId: request.liffId, body: Array.from(request.body) })
    });
    const response = await this.account.sendAccountRpc(request);
    SdkLogger.debug('LineLiff', `${request.method}Response`, { data: JSON.stringify(Array.from(response)) });
    return response;
  }
}
