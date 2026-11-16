import { MiniAppNavigationController } from '../../web/MiniAppNavigationController';
import { LineBinding } from './LineVendor';

/** LINE 返回优先交给当前子窗口；普通网页历史仍复用公共导航。 */
export class LineNavigationController extends MiniAppNavigationController {
  goBack(): boolean {
    return this.closeChild() || super.goBack();
  }

  handleBackPress(): boolean {
    if (this.closeChild() || super.handleBackPress()) {
      return true;
    }
    // 宿主接入系统返回后，有网页历史时先回退；false 才表示可退出当前小程序。
    return this.endpoint?.session.isBackPressHandlingEnabled() === true && super.goBack();
  }

  handleHostGoBack(): void {
    this.goBack();
  }

  private closeChild(): boolean {
    if (!this.endpoint) {
      return false;
    }
    try {
      const binding = this.endpoint.session.getBinding();
      return binding instanceof LineBinding && binding.requestSubWindowClose();
    } catch (_) {
      // 旧视图关闭到导航解绑之间不再访问失效 Binding。
      return false;
    }
  }
}
