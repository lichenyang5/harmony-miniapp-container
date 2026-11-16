import { common } from '@kit.AbilityKit';
import { HostLifecycleMonitor } from './HostLifecycleMonitor';
import {
  MiniAppDescriptor, MiniAppSession
} from './Runtime';
import { MiniAppError } from './MiniAppError';
import { SdkLogger } from '../logging/SdkLogger';
import { HiLogSink } from '../logging/HiLogSink';
import { VendorRegistry } from './VendorRegistry';
import { INVALID_ARGUMENT, SESSION_CREATE_FAILED, VENDOR_NOT_SUPPORTED } from './MiniAppErrorCode';
import { MiniAppOptions } from './MiniAppOptions';
import { snapshotMiniAppInfo } from './MiniAppInfoSnapshot';
import { VendorAdapter } from './VendorAdapter';

/** 当前文件的 SDK 日志标识。 */
const TAG: string = 'SDK';

/** 当前模块使用的 SESSION_ID_PREFIX。 */
const SESSION_ID_PREFIX: string = 'mpsdk-';

/** SDK 内部懒加载运行时；同一模块运行环境共享一份实例，不持有当前页面或会话。 */
export class MiniAppSDK {
  private static vendors: VendorRegistry | undefined;
  private static sessionSequence: number = 0;

  private constructor() {
  }

  /** 在入口 UIAbility.onCreate 开头同步调用；重复调用不重置状态。 */
  static initialize(context: common.ApplicationContext): void {
    MiniAppSDK.getVendors();
    HostLifecycleMonitor.initialize((callback) => context.on('abilityLifecycle', callback));
  }

  /** @internal 容器使用；按厂商创建独立的默认适配器。 */
  static createDefaultAdapter(vendorId: string): VendorAdapter {
    const vendor = MiniAppSDK.getVendors().get(vendorId);
    if (!vendor) {
      throw new MiniAppError(VENDOR_NOT_SUPPORTED, 'SDK 暂不支持厂商：' + vendorId);
    }
    return vendor.createDefaultAdapter();
  }

  /**
   * @internal 容器使用；创建独立的会话及厂商绑定。
   * @param options 启动配置及当前宿主上下文。
   * @param adapter 厂商宿主适配器，每次创建独立的侧滑控制器。
   * @returns 新会话，关闭不会销毁共享运行时。
   * @throws 厂商未内置、参数无效或适配器尚未就绪时抛出异常。
   */
  static createSession(options: MiniAppOptions, adapter: VendorAdapter): MiniAppSession {
    const vendor = MiniAppSDK.getVendors().get(options.vendor);
    if (!vendor) {
      SdkLogger.debug(TAG, 'vendorRejected', { vendorId: options.vendor, code: VENDOR_NOT_SUPPORTED });
      throw new MiniAppError(VENDOR_NOT_SUPPORTED, 'SDK 暂不支持厂商：' + options.vendor);
    }
    if (adapter.vendorId !== options.vendor) {
      throw new MiniAppError(INVALID_ARGUMENT, 'Adapter 的 vendorId 与 options.vendor 不匹配');
    }
    SdkLogger.info(TAG, 'vendorSelected', { vendorId: vendor.vendorId });
    try {
      const descriptor: MiniAppDescriptor = {
        info: snapshotMiniAppInfo(options),
        vendor,
        adapter,
        swipeBackController: adapter.createSwipeBackController(options.uiContext),
        lifecycleController: options.lifecycleController,
        onClose: options.onClose,
        createWebRequestHandlers: options.createWebRequestHandlers,
        onOpenMiniApp: options.onOpenMiniApp
      };
      return new MiniAppSession(SESSION_ID_PREFIX + (++MiniAppSDK.sessionSequence), descriptor,
        options.uiAbilityContext);
    } catch (error) {
      throw MiniAppError.from(error as Object, SESSION_CREATE_FAILED, '创建小程序会话失败');
    }

  }

  /** 延迟建立内部状态，容器使用其他能力时仍可自动初始化。 */
  private static getVendors(): VendorRegistry {
    if (!MiniAppSDK.vendors) {
      SdkLogger.install(new HiLogSink());
      SdkLogger.info(TAG, 'initializing');
      MiniAppSDK.vendors = new VendorRegistry();
      SdkLogger.info(TAG, 'ready');
    }
    return MiniAppSDK.vendors;
  }
}
