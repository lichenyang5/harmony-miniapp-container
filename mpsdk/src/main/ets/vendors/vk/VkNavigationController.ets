import { MiniAppNavigationController } from '../../web/MiniAppNavigationController';
import { SdkLogger } from '../../logging/SdkLogger';
import { VkMiniAppIdentity, VkMiniAppIdentityBinding } from './VkMiniAppIdentity';

/** VK 联合历史返回的同步判定结果。 */
export enum VkMiniAppBackResult {
  BACKED = 'BACKED',
  BOUNDARY = 'BOUNDARY',
  UNAVAILABLE = 'UNAVAILABLE'
}

/** VK 页面菜单和应用内历史回退，每次挂载由 VkAdapter 独立创建。 */
export class VkNavigationController extends MiniAppNavigationController {
  private pendingBackIndex: number = -1;
  private pendingDocumentId: number = -1;
  private pendingBackAt: number = 0;

  /** 系统返回先应用侧滑策略，再复用页面按钮的安全返回和关闭流程。 */
  handleBackPress(): boolean {
    const endpoint = this.endpoint;
    if (!endpoint) {
      SdkLogger.info('VkNavigation', 'systemBackDecision', { code: 'ENDPOINT_UNAVAILABLE' });
      return false;
    }
    if (!endpoint.session.isBackPressHandlingEnabled()) {
      SdkLogger.info('VkNavigation', 'systemBackDecision', {
        sessionId: endpoint.session.id, code: 'HOST_FORWARDING_DISABLED'
      });
      return false;
    }
    if (super.handleBackPress()) {
      SdkLogger.info('VkNavigation', 'systemBackDecision', {
        sessionId: endpoint.session.id, code: 'CONSUMED_BY_SWIPE_POLICY'
      });
      return true;
    }
    this.requestSafeBack('systemBackDecision');
    return true;
  }

  /** VK 工具栏显式返回也不能回退到宿主；true 表示消费，不一定提交了历史回退。 */
  goBack(): boolean {
    if (!this.endpoint) {
      return false;
    }
    this.requestSafeBack('toolbarBackDecision');
    return true;
  }

  /** 网页显式返回不受 VKWebAppSetSwipeSettings 的侧滑开关影响。 */
  handleHostGoBack(): void {
    this.requestSafeBack('hostBackDecision');
  }

  /** 只在当前记录身份已确认时区分内部回退和小程序边界。 */
  navigateBackWithinMiniApp(): VkMiniAppBackResult {
    const endpoint = this.endpoint;
    if (!endpoint) {
      return VkMiniAppBackResult.UNAVAILABLE;
    }
    try {
      const binding = endpoint.session.getBinding() as VkMiniAppIdentityBinding;
      // 保留已验证的数字入口回退兼容；别名仍需实际识别后才能匹配。
      const identity = binding.miniAppIdentity ?? new VkMiniAppIdentity(endpoint.session.initialUrl);
      const entries = endpoint.controller.getBackForwardEntries();
      const index: number = entries.currentIndex;
      if (index < 0 || index >= entries.size || !identity.matches(entries.getItemAtIndex(index).historyUrl)) {
        return VkMiniAppBackResult.UNAVAILABLE;
      }
      if (index === 0 || !identity.matches(entries.getItemAtIndex(index - 1).historyUrl)) {
        this.pendingBackIndex = -1;
        return VkMiniAppBackResult.BOUNDARY;
      }
      const documentId: number = endpoint.session.getDocumentId();
      // backward 异步提交：短时合并相同历史位置上的重复返回。
      if (this.pendingBackIndex === index && this.pendingDocumentId === documentId &&
        Date.now() - this.pendingBackAt < 1000) {
        return VkMiniAppBackResult.BACKED;
      }
      this.pendingBackIndex = -1;
      endpoint.controller.backward();
      this.pendingBackIndex = index;
      this.pendingDocumentId = documentId;
      this.pendingBackAt = Date.now();
      return VkMiniAppBackResult.BACKED;
    } catch (_) {
      this.pendingBackIndex = -1;
      SdkLogger.warn('VkNavigation', 'backNavigationFailed', {
        sessionId: endpoint.session.id, code: 'WEB_BACK_FAILED'
      });
      return VkMiniAppBackResult.UNAVAILABLE;
    }
  }

  openMenu(): Promise<boolean> {
    return this.executeMenuAction('open');
  }

  closeMenu(): Promise<boolean> {
    return this.executeMenuAction('close');
  }

  private requestSafeBack(source: string): void {
    const endpoint = this.endpoint;
    if (!endpoint) {
      return;
    }
    const result = this.navigateBackWithinMiniApp();
    SdkLogger.info('VkNavigation', source, { sessionId: endpoint.session.id, code: result });
    if (result !== VkMiniAppBackResult.BOUNDARY || this.endpoint !== endpoint) {
      return;
    }
    try {
      endpoint.session.requestClose();
    } catch (_) {
      SdkLogger.warn('VkNavigation', 'backCloseFailed',
        { sessionId: endpoint.session.id, code: 'BACK_CLOSE_FAILED' });
    }
  }

  private async executeMenuAction(action: string): Promise<boolean> {
    const endpoint = this.endpoint;
    if (!endpoint) {
      return false;
    }
    try {
      const documentId = endpoint.session.getDocumentId();
      const completed = await endpoint.session.send(`(function () {
        if (typeof VKAppsActionMenuModal === 'undefined' ||
            typeof VKAppsActionMenuModal.${action} !== 'function') {
          throw new Error('VK action menu is unavailable');
        }
        VKAppsActionMenuModal.${action}();
      })();`);
      return completed && this.endpoint === endpoint && endpoint.session.getDocumentId() === documentId;
    } catch (_) {
      return false;
    }
  }
}
