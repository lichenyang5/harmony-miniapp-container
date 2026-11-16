import { WebRequestHandlerFactory } from './request/WebRequestTypes';
import { MiniAppLifecycleController } from '../core/lifecycle/MiniAppLifecycleController';
import { common } from '@kit.AbilityKit';
import { MiniAppInfo, MiniAppOptions, MiniAppOpenHandler } from '../core/MiniAppOptions';
import { MiniAppError } from '../core/MiniAppError';
import { SdkLogger } from '../logging/SdkLogger';
import { MiniAppSDK } from '../core/MiniAppSDK';
import { MiniAppSession } from '../core/Runtime';
import { MiniAppView } from './MiniAppView';
import { NOT_SUPPORTED, SESSION_CREATE_FAILED } from '../core/MiniAppErrorCode';
import { MiniAppNavigationController } from './MiniAppNavigationController';
import { VendorAdapter } from '../core/VendorAdapter';

/** 当前文件的 Container 日志标识。 */
const TAG: string = 'Container';


/** 宿主容器入口，内部完成厂商选择、会话创建、桥接绑定和资源释放。 */
@ComponentV2
export struct MiniAppContainer {
  /** 本次挂载的启动信息；切换小程序需要移除旧容器再创建新容器。 */
  @Require @Once @Param app: MiniAppInfo;
  /** 可选的宿主适配器；省略时由 app.vendor 对应厂商创建默认实例。 */
  @Once @Param adapter?: VendorAdapter = undefined;
  /** 可选的独立生命周期句柄；省略时默认选中，同一实例仅用于一次挂载。 */
  @Once @Param lifecycleController?: MiniAppLifecycleController = undefined;
  /** 每次挂载创建独立处理器；SDK 处理器优先。 */
  @Once @Param createWebRequestHandlers?: WebRequestHandlerFactory = undefined;
  private navigationController?: MiniAppNavigationController = undefined;
  @Local private session: MiniAppSession | undefined = undefined;
  @Local private errorMessage: string = '';
  /** 小程序主动关闭后通知宿主退出承载页面；通知前已清空内部网页状态。 */
  @Event onClose: () => void = (): void => {
  };
  /** 仅转交目标小程序；宿主负责创建承载页面，并在接受请求后完成 Promise。 */
  @Event onOpenMiniApp: MiniAppOpenHandler = async (_app: MiniAppInfo): Promise<void> => {
    throw new MiniAppError(NOT_SUPPORTED, 'Host mini app opening is unavailable');
  };
  /** WebView 已绑定导航句柄；不表示网页内容或厂商菜单已加载完成。 */
  @Event onNavigationReady: (controller: MiniAppNavigationController) => void =
    (_controller: MiniAppNavigationController): void => {
    };
  /** 启动失败或内部容器错误通知。 */
  @Event onError: (error: MiniAppError) => void = (_error: MiniAppError): void => {
  };

  /** 挂载时自动创建会话，将启动异常转换成可见提示及宿主事件。 */
  aboutToAppear(): void {
    try {
      SdkLogger.info(TAG, 'opening', { vendorId: this.app.vendor });
      const hostContext = this.getUIContext().getHostContext();
      if (!hostContext) {
        throw new MiniAppError(SESSION_CREATE_FAILED, '无法获取 UIAbilityContext');
      }
      const uiContext = this.getUIContext();
      const options: MiniAppOptions = {
        appId: this.app.appId,
        vendor: this.app.vendor,
        url: this.app.url,
        customUserAgent: this.app.customUserAgent,
        extraUserAgentParams: this.app.extraUserAgentParams,
        isSyncLoad: this.app.isSyncLoad,
        isOpenDomStorage: this.app.isOpenDomStorage,
        isOpenGeolocation: this.app.isOpenGeolocation,
        isOpenNewWindow: this.app.isOpenNewWindow,
        jsOnDocStart: this.app.jsOnDocStart,
        jsOnDocStartRules: this.app.jsOnDocStartRules,
        jsOnDocEnd: this.app.jsOnDocEnd,
        jsOnDocEndRules: this.app.jsOnDocEndRules,
        isSSLIgnore: this.app.isSSLIgnore,
        createWebRequestHandlers: this.createWebRequestHandlers,
        uiAbilityContext: hostContext as common.UIAbilityContext,
        uiContext,
        lifecycleController: this.lifecycleController,
        onOpenMiniApp: (app: MiniAppInfo): Promise<void> => this.onOpenMiniApp(app),
        onClose: (): void => {
          this.session = undefined;
          this.navigationController = undefined;
          this.errorMessage = '';
          this.onClose();
        }
      };
      const adapter = this.adapter ?? MiniAppSDK.createDefaultAdapter(this.app.vendor);
      this.navigationController = adapter.createNavigationController();
      this.session = MiniAppSDK.createSession(options, adapter);
      SdkLogger.info(TAG, 'prepared', { vendorId: this.app.vendor, sessionId: this.session.id });
    } catch (error) {
      this.reportError(MiniAppError.from(error as Object, SESSION_CREATE_FAILED, '创建小程序会话失败'));
    }
  }

  /** 移除时关闭会话，底层视图的重复关闭由会话幂等性保证安全。 */
  aboutToDisappear(): void {
    SdkLogger.info(TAG, 'removed', { vendorId: this.app.vendor, sessionId: this.session?.id });
    this.session?.close();
    this.session = undefined;
  }

  /** 成功时展示内部 WebView；未就绪时显示真实状态，不加载假兼容页面。 */
  build() {
    Column() {
      if (this.session) {
        MiniAppView({
          session: this.session,
          navigationController: this.navigationController,
          onNavigationReady: (controller: MiniAppNavigationController): void => {
            this.onNavigationReady(controller);
          },
          onError: (error: MiniAppError): void => {
            this.reportError(error);
          }
        })
      } else if (this.errorMessage) {
        Text(this.errorMessage)
          .padding(16)
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 释放失败实例，显示说明并通知宿主。 */
  private reportError(error: MiniAppError): void {
    SdkLogger.error(TAG, 'failed', error, {
      vendorId: this.app.vendor,
      sessionId: this.session?.id
    });
    this.session?.close();
    this.session = undefined;
    this.errorMessage = error.message;
    this.onError(error);
  }
}
