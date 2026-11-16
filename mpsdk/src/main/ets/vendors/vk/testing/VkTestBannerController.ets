import { MiniAppError } from '../../../core/MiniAppError';
import { CAPABILITY_BUSY, DOCUMENT_CHANGED, SESSION_CLOSED, SYSTEM_ERROR } from '../../../core/MiniAppErrorCode';

/** 仅本地测试素材的展示配置，不代表 VK 广告库存。 */
export interface VkTestBannerState {
  id: number;
  location: string;
  layout: string;
  canClose: boolean;
}

export interface VkTestBannerResult {
  result: boolean;
  banner_width?: number;
  banner_height?: number;
  banner_location?: string;
  layout_type?: string;
}

/** 每个 binding 独占；宿主必须在真实布局/移除后确认，不能直接回报成功。 */
export class VkTestBannerController {
  private state?: VkTestBannerState;
  private measured?: VkTestBannerResult;
  private sequence: number = 0;
  private closed: boolean = false;
  private hiding: boolean = false;
  private timer?: number;
  private resolve?: (result: VkTestBannerResult) => void;
  private reject?: (error: MiniAppError) => void;
  private readonly onChange: (state?: VkTestBannerState) => void;

  constructor(onChange: (state?: VkTestBannerState) => void) {
    this.onChange = onChange;
  }

  show(location: string, layout: string, canClose: boolean): Promise<VkTestBannerResult> {
    this.ensureActive();
    if (this.state) {
      throw new MiniAppError(CAPABILITY_BUSY, '本地测试横幅已展示或正在切换');
    }
    this.state = {
      id: ++this.sequence,
      location,
      layout,
      canClose
    };
    return this.waitForUi(false);
  }

  check(): VkTestBannerResult {
    this.ensureActive();
    return this.snapshot();
  }

  hide(): Promise<VkTestBannerResult> {
    this.ensureActive();
    if (!this.state) {
      const result: VkTestBannerResult = { result: false };
      return Promise.resolve(result);
    }
    if (this.hiding && this.resolve !== undefined) {
      throw new MiniAppError(CAPABILITY_BUSY, '本地测试横幅正在隐藏');
    }
    // 展示未完成时也允许隐藏，但不能把未展示素材的 Hide 回报为 true。
    this.cancelPending(new MiniAppError(SYSTEM_ERROR, '本地测试横幅展示已取消'));
    return this.waitForUi(true);
  }

  /** 参数为宿主测得的物理像素，而非硬编码 vp 或其他设备截图中的尺寸。 */
  confirmLayout(id: number, widthPx: number, heightPx: number): void {
    if (this.closed || !this.state || this.state.id !== id || this.hiding) {
      return;
    }
    if (!Number.isFinite(widthPx) || !Number.isFinite(heightPx) || widthPx < 1 || heightPx < 1) {
      this.measured = undefined;
      return;
    }
    this.measured = {
      result: true,
      banner_width: Math.round(widthPx),
      banner_height: Math.round(heightPx),
      banner_location: this.state.location,
      layout_type: this.state.layout
    };
    const finish = this.resolve;
    this.clearPending();
    finish?.(this.snapshot());
  }

  /** 仅接受同一素材的消失事件，迟到的旧组件回调不能清掉新横幅。 */
  confirmHidden(id: number): void {
    if (this.closed || !this.state || this.state.id !== id) {
      return;
    }
    const result = this.snapshot();
    const finish = this.hiding ? this.resolve : undefined;
    if (!this.hiding) {
      this.cancelPending(new MiniAppError(SYSTEM_ERROR, '本地测试横幅已移除'));
    }
    this.clearPending();
    this.state = undefined;
    this.measured = undefined;
    this.hiding = false;
    finish?.(result);
  }

  async closeByUser(id: number): Promise<void> {
    if (!this.state || this.state.id !== id || !this.state.canClose ||
      (this.hiding && this.resolve !== undefined)) {
      return;
    }
    await this.hide();
  }

  reset(): void {
    const hadState = this.state !== undefined;
    this.cancelPending(new MiniAppError(DOCUMENT_CHANGED, '本地测试横幅页面已切换'));
    this.state = undefined;
    this.measured = undefined;
    this.hiding = false;
    if (hadState) {
      this.notifyRemoval();
    }
  }

  dispose(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.reset();
  }

  private ensureActive(): void {
    if (this.closed) {
      throw new MiniAppError(SESSION_CLOSED, '本地测试横幅已释放');
    }
  }

  private snapshot(): VkTestBannerResult {
    if (!this.measured) {
      return { result: false };
    }
    return {
      result: true,
      banner_width: this.measured.banner_width,
      banner_height: this.measured.banner_height,
      banner_location: this.measured.banner_location,
      layout_type: this.measured.layout_type
    };
  }

  private waitForUi(hiding: boolean): Promise<VkTestBannerResult> {
    this.hiding = hiding;
    return new Promise<VkTestBannerResult>((resolve, reject): void => {
      this.resolve = resolve;
      this.reject = reject;
      this.timer = setTimeout((): void => {
        this.failUi(new MiniAppError(SYSTEM_ERROR, '本地测试横幅未收到 UI 确认'));
      }, 3000);
      try {
        // 拷贝配置，宿主不能通过修改引用篡改内部状态。
        const view: VkTestBannerState | undefined = !hiding && this.state ? {
          id: this.state.id,
          location: this.state.location,
          layout: this.state.layout,
          canClose: this.state.canClose
        } : undefined;
        this.onChange(view);
      } catch (error) {
        this.failUi(new MiniAppError(SYSTEM_ERROR, '本地测试横幅 UI 操作失败', error as Object));
      }
    });
  }

  private failUi(error: MiniAppError): void {
    const wasHiding = this.hiding;
    this.cancelPending(error);
    // 未收到移除确认时保留最后确认的状态，并允许再次 Hide；不能谎报已消失。
    this.hiding = true;
    if (!wasHiding) {
      this.notifyRemoval();
    }
  }

  private notifyRemoval(): void {
    try {
      this.onChange(undefined);
    } catch (_) { /* 宿主销毁异常不能阻断 SDK 清理。 */
    }
  }

  private cancelPending(error: MiniAppError): void {
    const fail = this.reject;
    this.clearPending();
    fail?.(error);
  }

  private clearPending(): void {
    if (this.timer !== undefined) {
      clearTimeout(this.timer);
    }
    this.timer = undefined;
    this.resolve = undefined;
    this.reject = undefined;
  }
}
