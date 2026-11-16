import { url } from '@kit.ArkTS';
import { MiniAppSession, SessionWebSchemeRequest } from '../../../core/Runtime';
import { INVALID_ARGUMENT } from '../../../core/MiniAppErrorCode';
import { SdkLogger } from '../../../logging/SdkLogger';
import { WebSchemeChain, WebSchemeDecision, WebSchemeHandler } from '../../../web/scheme/WebSchemeTypes';
import { LineAdapter } from '../LineAdapter';
import { LINE_SHARE_PICKER_BRIDGE_NAME } from '../LineConstants';
import { LINE_APP_SCHEME, LINE_SHARE_PICKER_HOST } from './LineSchemeConstants';

interface LineSharePickerRequest {
  liffId: string;
  ott: string;
  data: string;
}

/** 仅 WEB_HOOK 注册；消费客户端 picker 命令，交给当前文档预建的网页窗口。 */
export class LineSharePickerSchemeHandler implements WebSchemeHandler<SessionWebSchemeRequest> {
  readonly id: string = 'line.share-picker';
  private readonly session: MiniAppSession;
  private readonly route: RegExp =
    new RegExp('^' + LINE_APP_SCHEME + '://' + LINE_SHARE_PICKER_HOST + '(?:[/?#]|$)', 'i');
  private disposed: boolean = false;

  constructor(session: MiniAppSession) {
    this.session = session;
  }

  supports(request: SessionWebSchemeRequest): boolean {
    return this.route.test(request.url);
  }

  handle(request: SessionWebSchemeRequest, _chain: WebSchemeChain): WebSchemeDecision {
    if (this.disposed || this.session.isClosed() || !request.isMainFrame ||
      request.documentId !== this.session.getDocumentId() || !this.session.lifecycle.isForeground()) {
      return WebSchemeDecision.BLOCK;
    }
    try {
      const payload = this.parseRequest(request.url);
      const receiver: string = 'window.' + LINE_SHARE_PICKER_BRIDGE_NAME;
      // 仅交付 JSON 数据，URL 中的消息正文不能作为脚本执行。
      const script: string = receiver + ' && ' + receiver + '.accept(' +
        JSON.stringify(payload) + ');';
      this.session.send(script);
      return WebSchemeDecision.CONSUME;
    } catch (_) {
      SdkLogger.warn('LineSharePicker', 'requestRejected', { code: INVALID_ARGUMENT });
      return WebSchemeDecision.BLOCK;
    }
  }

  dispose(): void {
    this.disposed = true;
  }

  private parseRequest(address: string): LineSharePickerRequest {
    const parsed = new url.URL(address);
    if (parsed.protocol !== LINE_APP_SCHEME + ':' || parsed.hostname !== LINE_SHARE_PICKER_HOST ||
      parsed.username || parsed.password || parsed.port || parsed.hash ||
      (parsed.pathname !== '' && parsed.pathname !== '/') ||
      (parsed.params.has('closeModals') && parsed.params.get('closeModals') !== 'false')) {
      throw new Error('Invalid picker URL');
    }
    const payload: LineSharePickerRequest = {
      liffId: this.requiredParameter(parsed, 'liffId'),
      ott: this.requiredParameter(parsed, 'ott'),
      data: this.requiredParameter(parsed, 'data')
    };
    const expected = this.session.getAdapter<LineAdapter>().getLiffId(this.session) ?? this.session.appId;
    if (payload.liffId !== expected) throw new Error('Picker does not belong to this session');
    return payload;
  }

  /** 不接受重复键，避免原生侧与网页侧对同一协议取到不同参数。 */
  private requiredParameter(address: url.URL, name: string): string {
    const values = address.params.getAll(name);
    if (values.length !== 1 || !values[0]) throw new Error('Invalid picker parameter');
    return values[0];
  }
}
