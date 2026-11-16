import { VkTestBannerController, VkTestBannerState } from './VkTestBannerController';
import { SdkLogger } from '../../../logging/SdkLogger';

export interface VkTestNativeAdState {
  id: number;
}

export interface VkTestNativeAdResult {
  result: boolean;
}

/** 本地插屏素材。复用横幅已验证的 UI 确认机制，但资源、状态与横幅独立。 */
export class VkTestNativeAdController {
  private readonly view: VkTestBannerController;
  private activeId?: number;
  private mounted: boolean = false;
  private disposed: boolean = false;

  constructor(onChange: (state?: VkTestNativeAdState) => void) {
    this.view = new VkTestBannerController((state?: VkTestBannerState): void => {
      if (state) {
        this.activeId = state.id;
        this.mounted = false;
        const nativeState: VkTestNativeAdState = { id: state.id };
        onChange(nativeState);
      } else {
        const id = this.activeId;
        onChange(undefined);
        // 宿主已接受移除，且组件尚未挂载时，不会再收到 onDisAppear。
        if (id !== undefined && !this.mounted) {
          this.confirmHidden(id);
        }
      }
    });
  }

  /** 内置本地素材空闲时可展示；绝不代表 VK 服务端库存。 */
  check(): VkTestNativeAdResult {
    return { result: !this.disposed && this.activeId === undefined };
  }

  async show(): Promise<VkTestNativeAdResult> {
    const result = await this.view.show('bottom', 'overlay', true);
    return { result: result.result };
  }

  /** 宿主组件 aboutToAppear 时调用，早于布局确认。 */
  confirmMounted(id: number): void {
    if (!this.disposed && this.activeId === id) {
      this.mounted = true;
    }
  }

  confirmShown(id: number, widthPx: number, heightPx: number): void {
    this.confirmMounted(id);
    this.view.confirmLayout(id, widthPx, heightPx);
  }

  confirmHidden(id: number): void {
    if (this.activeId !== id) {
      return;
    }
    this.view.confirmHidden(id);
    this.activeId = undefined;
    this.mounted = false;
  }

  async close(): Promise<void> {
    if (this.activeId !== undefined) {
      await this.view.closeByUser(this.activeId);
    }
  }

  hasActiveAd(): boolean {
    return !this.disposed && this.activeId !== undefined;
  }

  /** 先关闭本地插屏，不能将同一次返回手势继续传递为退出元服务。 */
  handleBackPress(): boolean {
    if (!this.hasActiveAd()) {
      return false;
    }
    this.close().catch((): void => {
      SdkLogger.warn('VkTestNativeAd', 'closeFailed');
    });
    return true;
  }

  reset(): void {
    this.view.reset();
    this.activeId = undefined;
    this.mounted = false;
  }

  dispose(): void {
    this.disposed = true;
    this.view.dispose();
    this.activeId = undefined;
    this.mounted = false;
  }
}
