import { SwipeBackTools } from '../capabilities/swipe/SwipeBackTools';
import { SwipeBackController, VendorAdapter } from './VendorAdapter';
import { MiniAppNavigationController } from '../web/MiniAppNavigationController';
import { MiniAppError } from './MiniAppError';
import { NOT_SUPPORTED } from './MiniAppErrorCode';

/** 厂商宿主接口的类型化容器，不持有当前会话或侧滑控制器。 */
export abstract class MiniAppAdapter<T> implements VendorAdapter {
  abstract readonly vendorId: string;
  protected readonly host: T;

  constructor(host: T) {
    this.host = host;
  }

  /** 每次挂载创建独立导航句柄，绑定和解绑由视图负责。 */
  createNavigationController(): MiniAppNavigationController {
    return new MiniAppNavigationController();
  }

  createSwipeBackController(uiContext: UIContext): SwipeBackController {
    return new SwipeBackTools(uiContext, (enabled: boolean): void => {
      if (!canIUse('SystemCapability.ArkUI.ArkUI.Circle')) {
        throw new MiniAppError(NOT_SUPPORTED, '请由宿主接入页面返回事件处理');
      }
      uiContext.enableSwipeBack(enabled);
    });
  }
}
