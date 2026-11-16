import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { assertHostForeground } from '../../core/HostLifecycleMonitor';
import { SystemLinkScheme } from '../../capabilities/links/SystemLinkConstants';
import { SystemLinkTools } from '../../capabilities/links/SystemLinkTools';
import { MiniAppError } from '../../core/MiniAppError';
import { NOT_SUPPORTED, SYSTEM_ERROR } from '../../core/MiniAppErrorCode';
import { SdkLogger } from '../../logging/SdkLogger';
import { WebSchemeChain, WebSchemeDecision, WebSchemeHandler, WebSchemeRequest } from './WebSchemeTypes';

/** 由厂商显式注册的公共系统协议入口，每个 WebView 独立持有。 */
export class WebSystemSchemeHandler implements WebSchemeHandler<WebSchemeRequest> {
  readonly id: string = 'web.system';
  private readonly context: common.UIAbilityContext;
  private readonly tools: SystemLinkTools;
  private disposed: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.tools = new SystemLinkTools(context);
  }

  supports(request: WebSchemeRequest): boolean {
    const separator: number = request.url.indexOf(':');
    const scheme: string = separator < 0 ? '' : request.url.slice(0, separator).toLowerCase();
    return scheme === SystemLinkScheme.TEL || scheme === SystemLinkScheme.MAILTO || scheme === SystemLinkScheme.SMS;
  }

  handle(request: WebSchemeRequest, _chain: WebSchemeChain): WebSchemeDecision {
    SdkLogger.info('WebSystemScheme', 'received', { code: request.isMainFrame ? 'MAIN_FRAME' : 'SUBFRAME' });
    SdkLogger.debug('WebSystemScheme', 'request', { data: request.url });
    if (this.disposed || !request.isMainFrame) {
      SdkLogger.debug('WebSystemScheme', 'blocked', {
        code: this.disposed ? 'DISPOSED' : 'SUBFRAME'
      });
      return WebSchemeDecision.BLOCK;
    }
    // 系统面板未返回结果不代表后续点击无效；每次导航独立交给平台处理。
    this.open(request).catch((error: Object): void => {
      SdkLogger.warn('WebSystemScheme', 'failurePromptFailed', {
        code: MiniAppError.from(error, SYSTEM_ERROR, 'Unable to show system link failure').code
      });
    });
    return WebSchemeDecision.CONSUME;
  }

  dispose(): void {
    this.disposed = true;
  }

  private async open(request: WebSchemeRequest): Promise<void> {
    try {
      await this.tools.open(request.url);
    } catch (error) {
      const failure = MiniAppError.from(error, SYSTEM_ERROR, 'Unable to open system link');
      const host = await window.getLastWindow(this.context);
      assertHostForeground(this.context);
      host.getUIContext().getPromptAction().showToast({ message: failure.code === NOT_SUPPORTED ?
        $r('app.string.mp_web_system_link_unavailable') : $r('app.string.mp_web_system_link_failed') });
    }
  }
}
