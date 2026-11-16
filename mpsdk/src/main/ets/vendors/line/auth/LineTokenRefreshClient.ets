import { LineRpcPath, LineTokenRefreshRpcMethod } from '../network/LineRpcConstants';
import { LineTransport, LineClientRole, LineAccessKind } from '../network/LineTransport';
import { LineRefreshTokenResult } from './LineAccountTypes';
import { LineTokenRefreshCodec } from './LineTokenRefreshCodec';

/** Token 刷新与报告 RPC。凭据更新、调用顺序和账号代次归账号管理器负责。 */
export class LineTokenRefreshClient {
  private sequence: number = 0;
  private readonly transport: LineTransport;

  constructor(transport: LineTransport) {
    this.transport = transport;
  }

  async refresh(refreshToken: string, accessToken: string, role?: LineClientRole): Promise<LineRefreshTokenResult> {
    const sequence: number = ++this.sequence;
    const bytes = await this.transport.send({
      path: LineRpcPath.REFRESH,
      method: LineTokenRefreshRpcMethod.REFRESH,
      body: LineTokenRefreshCodec.encodeRefreshToken(refreshToken, sequence),
      sessionAccess: accessToken,
      role, accessKind: role === undefined ? undefined : LineAccessKind.ACCOUNT
    });
    return LineTokenRefreshCodec.decodeRefreshToken(bytes, sequence);
  }

  async reportRefreshedAccessToken(accessToken: string, role?: LineClientRole): Promise<void> {
    const sequence: number = ++this.sequence;
    const bytes = await this.transport.send({
      path: LineRpcPath.REFRESH,
      method: LineTokenRefreshRpcMethod.REPORT,
      body: LineTokenRefreshCodec.encodeReportRefreshedAccessToken(accessToken, sequence),
      sessionAccess: accessToken,
      role, accessKind: role === undefined ? undefined : LineAccessKind.ACCOUNT
    });
    LineTokenRefreshCodec.decodeReportRefreshedAccessToken(bytes, sequence);
  }
}
