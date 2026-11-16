import { VendorBinding } from '../../core/Runtime';

/** 入口意图和实际 iframe 身份按会话绑定；不把普通 VK 路径自动当作小程序。 */
export class VkMiniAppIdentity {
  private readonly entryRoute: string;
  private appId: string;
  private disposed: boolean = false;

  constructor(initialUrl: string) {
    this.entryRoute = VkMiniAppIdentity.route(initialUrl);
    this.appId = VkMiniAppIdentity.numericId(this.entryRoute);
  }

  static route(address: string): string {
    // 登录后 VK 可将 /app<ID> 重定向到 /games/app<ID>；保留应用号，不能归并为 /games。
    const game = /^https:\/\/(?:m\.)?vk\.(?:ru|com)\/games\/(app[0-9]+)(?:\/[^?#]*)?(?:[?#].*)?$/i.exec(address);
    if (game) {
      return '/' + game[1];
    }
    // VKWebAppSetLocation may append an internal route after the app alias/app id.
    // Identity belongs to the first path segment; the suffix is miniapp navigation state.
    const match = /^https:\/\/(?:m\.)?vk\.(?:ru|com)(\/[A-Za-z0-9_.-]+)(?:\/[^?#]*)?\/?(?:[?#].*)?$/i.exec(address);
    const route: string = match ? match[1] : '';
    return /^\/(?:feed|login|join|auth|settings|im|friends|news|support|games)$/i.test(route) ? '' : route;
  }

  private static numericId(route: string): string {
    const match = /^\/app([0-9]+)$/i.exec(route);
    return match ? match[1] : '';
  }

  /** 由顶层脚本确认唯一带启动参数的 iframe 后上报，不作签名验证或权限依据。 */
  identify(hostUrl: string, appId: string): boolean {
    if (this.disposed || !this.entryRoute || typeof appId !== 'string' || !/^[0-9]+$/.test(appId)) {
      return false;
    }
    const route = VkMiniAppIdentity.route(hostUrl);
    if (!route || (route !== this.entryRoute && VkMiniAppIdentity.numericId(route) !== appId)) {
      return false;
    }
    if (this.appId && this.appId !== appId) {
      return false;
    }
    this.appId = appId;
    return true;
  }

  matches(address: string): boolean {
    if (this.disposed || !this.appId) {
      return false;
    }
    const route = VkMiniAppIdentity.route(address);
    return route !== '' && (route === this.entryRoute || VkMiniAppIdentity.numericId(route) === this.appId);
  }

  dispose(): void {
    this.disposed = true;
    this.appId = '';
  }
}

/** 只在 VK 模块内读取，公共 VendorBinding 不增加厂商字段。 */
export interface VkMiniAppIdentityBinding extends VendorBinding {
  readonly miniAppIdentity?: VkMiniAppIdentity;
}
