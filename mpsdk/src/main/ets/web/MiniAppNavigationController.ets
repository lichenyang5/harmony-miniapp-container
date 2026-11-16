import { url } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { MiniAppError } from '../core/MiniAppError';
import { INVALID_ARGUMENT, WEB_NOT_ATTACHED, WEB_CONTAINER_FAILED } from '../core/MiniAppErrorCode';
import { HostNavigationHandler, MiniAppSession } from '../core/Runtime';

/** 当前视图的导航端点及其关联的 WebView、会话。 */
export interface MiniAppNavigationEndpoint {
  readonly controller: webview.WebviewController;
  readonly session: MiniAppSession;

  goHome(): void;

  refresh(): void;

  navigateTo(address: string): Promise<void>;

}

/** 宿主用于控制当前小程序页面导航的句柄。 */
export class MiniAppNavigationController implements HostNavigationHandler {
  protected endpoint: MiniAppNavigationEndpoint | undefined = undefined;

  /** 由容器内部绑定当前可用的网页实例。 */
  attach(endpoint: MiniAppNavigationEndpoint): void {
    this.endpoint = endpoint;
  }

  /** 仅解绑传入实例，避免旧视图销毁时误解绑新视图。 */
  detach(endpoint: MiniAppNavigationEndpoint): void {
    if (this.endpoint === endpoint) {
      this.endpoint = undefined;
    }
  }

  /** 在当前会话和 WebView 中跳转；厂商校验地址属于当前小程序并准备加载。 */
  async navigateTo(address: string): Promise<void> {
    const endpoint = this.endpoint;
    if (!endpoint) {
      throw new MiniAppError(WEB_NOT_ATTACHED, 'Mini app view is unavailable');
    }
    try {
      if (typeof address !== 'string' || !/^https?:\/\/[^/?#\\]+/i.test(address) || /[\u0000-\u0020\u007f]/.test(address)) {
        throw new MiniAppError(INVALID_ARGUMENT, 'Invalid mini app URL');
      }
      const parsed: url.URL = new url.URL(address);
      if (!parsed.hostname || parsed.username || parsed.password) {
        throw new MiniAppError(INVALID_ARGUMENT, 'Invalid mini app URL');
      }
    } catch (error) {
      throw MiniAppError.from(error as Object, INVALID_ARGUMENT, 'Invalid mini app URL');
    }
    try {
      await endpoint.navigateTo(address);
    } catch (error) {
      throw MiniAppError.from(error as Object, WEB_CONTAINER_FAILED, 'Navigating mini app failed');
    }
  }

  /** 返回小程序配置的入口页；容器尚未就绪时不执行操作。 */
  goHome(): void {
    this.endpoint?.goHome();
  }

  /** 刷新当前页面；容器尚未就绪时不执行操作。 */
  refresh(): void {
    this.endpoint?.refresh();
  }

  /** 工具栏主动回退网页历史；未绑定或无历史返回 false，平台失败抛出异常。 */
  goBack(): boolean {
    const endpoint = this.endpoint;
    if (!endpoint) {
      return false;
    }
    try {
      if (!endpoint.controller.accessBackward()) {
        return false;
      }
      endpoint.controller.backward();
      return true;
    } catch (error) {
      throw MiniAppError.from(error as Object, WEB_CONTAINER_FAILED, '网页返回失败');
    }
  }

  /** 在 onNavigationReady 中调用，并在宿主 onBackPress 中转发 handleBackPress。 */
  enableBackPressHandling(): void {
    this.endpoint?.session.enableBackPressHandling();
  }

  /** 同步返回是否消费系统返回事件；包含侧滑和返回键，不操作网页历史。 */
  handleBackPress(): boolean {
    return this.endpoint?.session.handleBackPress() ?? false;
  }

  /** 普通厂商不处理网页宿主的显式返回请求。 */
  handleHostGoBack(): void {
  }

  /** 默认不支持菜单，由厂商导航子类实现。 */
  openMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  /** 默认不支持菜单，由厂商导航子类实现。 */
  closeMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }
}
