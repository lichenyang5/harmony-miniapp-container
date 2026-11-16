import { BridgeContext } from '../../../core/Runtime';
import { MiniAppError } from '../../../core/MiniAppError';
import { INVALID_ARGUMENT, NOT_SUPPORTED, SESSION_CLOSED } from '../../../core/MiniAppErrorCode';
import { ParamAssert } from '../../../utils/ParamAssert';
import { LINE_OPEN_WINDOW_METHOD, LINE_VENDOR_ID } from '../LineConstants';
import { LineBridgeError } from '../LineBridgeError';
import { LineEventContext } from '../LineEventContext';
import { LineEventHandler } from '../LineEventHandler';
import { LineBrowserHost } from '../browser/LineBrowserHost';
import { validateLineBrowserUrl } from '../browser/LineBrowserUrl';
import { resolveLineLiffUrl } from '../liff/LineLiffUrl';
import { MiniAppInfo } from '../../../core/MiniAppOptions';

interface LineOpenWindowParams {
  url: string;
  external?: boolean;
}

interface LineOpenWindowResult {}

interface LineOpenWindowRoute {
  kind: 'browser' | 'liff';
  url: string;
  appId?: string;
}

/** 打开入口接受请求后返回空回包，不等待网页加载或目标关闭。 */
export class LineOpenWindowHandler implements LineEventHandler<LineOpenWindowResult> {
  readonly context: BridgeContext;
  readonly type: string = LINE_OPEN_WINDOW_METHOD;
  readonly ext: boolean = true
  private readonly browser: LineBrowserHost;
  private disposed: boolean = false;

  constructor(context: BridgeContext, browser: LineBrowserHost) {
    this.context = context;
    this.browser = browser;
  }

  async handle(params: object, _request: LineEventContext): Promise<LineOpenWindowResult> {
    if (this.disposed || this.context.lifecycle?.isForeground() === false) {
      throw new MiniAppError(SESSION_CLOSED, 'LINE open handler is closed');
    }
    try {
      ParamAssert.assertObject(params, 'params');
      const values: LineOpenWindowParams = params as LineOpenWindowParams;
      ParamAssert.assertString(values.url, 'url', false);
      ParamAssert.assertOptionalBoolean(values.external, 'external');
      const route = this.resolveLineOpenWindow(values.url, values.external ?? false);
      if (route.kind === 'liff') {
        const app: MiniAppInfo = { appId: route.appId!, vendor: LINE_VENDOR_ID, url: route.url };
        await this.openMiniApp(app);
      } else {
        await this.browser.open(route.url);
      }
      return {};
    } catch (error) {
      throw LineBridgeError.invalidArgument(error as Object);
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
  }

  /** 浏览器深链与 Bridge 请求共用所属会话的宿主回调。 */
  private async openMiniApp(app: MiniAppInfo): Promise<void> {
    if (this.disposed || this.context.lifecycle?.isForeground() === false) {
      throw new MiniAppError(SESSION_CLOSED, 'LINE open handler is closed');
    }
    if (!this.context.requestOpenMiniApp) {
      throw new MiniAppError(NOT_SUPPORTED, 'Host mini app opening is unavailable');
    }
    await this.context.requestOpenMiniApp(app);
  }

  /** 分类入口地址；状态以原编码包装，避免重复查询或 fragment 丢失。 */
  private resolveLineOpenWindow(address: string, external: boolean): LineOpenWindowRoute {
    try {
      const parsed = validateLineBrowserUrl(address);
      if (external) {
        return { kind: 'browser', url: address };
      }
      const target = resolveLineLiffUrl(address, parsed);
      if (target) {
        return {
          kind: 'liff',
          url: target.url,
          appId: target.appId
        };
      }
      // 元服务宿主无法外跳；普通网页与 external=true 均由 LINE 内置浏览器承载。
      return { kind: 'browser', url: address };
    } catch (error) {
      throw MiniAppError.from(error as Object, INVALID_ARGUMENT, 'Invalid open window URL');
    }
  }

}
