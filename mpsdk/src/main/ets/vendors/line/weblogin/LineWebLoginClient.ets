import { LineLiffAccount, LineLiffClient } from '../liff/LineLiffClient';
import { SdkLogger } from '../../../logging/SdkLogger';
import { LineRpcPath, LineRpcTimeout } from '../network/LineRpcConstants';
import { LineWebLoginCodec } from './LineWebLoginCodec';
import { LineWebLoginInput, LineWebLoginResult, LineWebLoginSource } from './LineWebLoginTypes';

/** 不拥有账号生命周期；LIFF 复用一次刷新，Channel 保持其独立异常契约。 */
export class LineWebLoginClient {
  private readonly source: LineWebLoginSource;
  private readonly account: LineLiffAccount;
  private readonly liffId: string;
  private readonly liff: LineLiffClient;
  private sequence: number = 0;

  constructor(source: LineWebLoginSource, account: LineLiffAccount, liffId: string = '') {
    this.source = source;
    this.account = account;
    this.liffId = liffId;
    this.liff = new LineLiffClient(account);
  }

  async request(input: LineWebLoginInput, allowed: boolean): Promise<LineWebLoginResult> {
    const sequence: number = ++this.sequence;
    const method: string = LineWebLoginCodec.method(this.source, allowed);
    const body = LineWebLoginCodec.encode(this.source, input, allowed, sequence);
    const startedAt: number = Date.now();
    SdkLogger.info('LineWebLogin', `${method}Started`);
    if (this.source === 'browser') {
      SdkLogger.debug('LineWebLogin', `${method}Request`, { data: JSON.stringify(Array.from(body)) });
    }
    let decoded: LineWebLoginResult | undefined;
    const inspect = (bytes: Uint8Array): void => {
      if (this.source === 'browser') {
        SdkLogger.debug('LineWebLogin', `${method}Response`, { data: JSON.stringify(Array.from(bytes)) });
      }
      decoded = LineWebLoginCodec.decode(this.source, bytes, allowed, sequence);
    };
    const response = this.source === 'browser' ? await this.account.sendAccountRpc({
      path: LineRpcPath.CHANNEL, method, body, timeoutMs: LineRpcTimeout.REQUEST_MS
    }) : await this.liff.send(method, body, this.liffId, sequence, inspect);
    SdkLogger.info('LineWebLogin', `${method}Received`, { durationMs: Date.now() - startedAt });
    // LIFF 首次回复已在一次刷新判定中检查；Channel 或刷新后的回复在此检查。
    if (!decoded) {
      inspect(response);
    }
    return decoded!;
  }
}
