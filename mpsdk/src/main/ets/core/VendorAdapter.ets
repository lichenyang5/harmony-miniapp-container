import { MiniAppNavigationController } from '../web/MiniAppNavigationController';

/** 每次创建会话时产生的独立侧滑控制器，由会话负责释放。 */
export interface SwipeBackController {
  setEnabled(enabled: boolean): void;

  dispose(): void;
}

/** 核心只识别厂商身份和会话资源工厂，不解释厂商业务回调。 */
export interface VendorAdapter {
  readonly vendorId: string;

  createNavigationController(): MiniAppNavigationController;

  createSwipeBackController(uiContext: UIContext): SwipeBackController;
}
