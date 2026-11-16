import { VkBridgeError } from './VkBridgeError';
import { VkClientErrorCode } from './VkClientErrorCode';
import { VK_VENDOR_ID } from './VkVendor';
import { MiniAppAdapter } from '../../core/MiniAppAdapter';
import { VkNavigationController } from './VkNavigationController';
import { MiniAppNavigationController } from '../../web/MiniAppNavigationController';
import { VkTestBannerController } from './testing/VkTestBannerController';
import { VkTestNativeAdController } from './testing/VkTestNativeAdController';
import BuildProfile from '../../../../../BuildProfile';

/** VK 应用号，与宿主业务 appId 不同。 */
export interface AuthTokenRequest {
  appId: number;
  scope: string;
}

export interface AuthTokenResult {
  accessToken: string;
  scope: string;
}

export type AuthTokenRequestHandler = (request: AuthTokenRequest) => Promise<AuthTokenResult>;

export type ClientMessageHandler = (fragment?: string) => void;

export interface UserInfoRequest {
  userId?: number;
  userIds?: string;
}

/** VK 用户资料中的城市或国家。 */
export interface UserInfoLocation {
  id: number;
  title: string;
}

/** 宿主用户服务返回的 VK 用户资料。 */
export interface UserInfoResult {
  id: number;
  firstName: string;
  lastName: string;
  sex: number;
  city: UserInfoLocation;
  country: UserInfoLocation;
  birthDate?: string;
  birthDateVisibility: number;
  canAccessClosed: boolean;
  isClosed: boolean;
  photo100: string;
  photo200: string;
  photoMaxOriginal?: string;
  timezone?: number;
}

/** 当前会话向宿主请求 VK 用户资料的异步回调。 */
export type UserInfoRequestHandler = (request: UserInfoRequest) => Promise<UserInfoResult>;

export interface VkHost {
  /** 仅 Debug 本地素材测试；默认不配置，每个会话必须新建独立控制器。 */
  createTestBanner?: () => VkTestBannerController;

  /** 仅 Debug 本地插屏测试；每个会话必须新建控制器，不能提供模拟奖励。 */
  createTestNativeAd?: () => VkTestNativeAdController;
  onUserInfoRequest?: UserInfoRequestHandler;
  onAuthTokenRequest?: AuthTokenRequestHandler;
  onClientMessage?: ClientMessageHandler;
}

/** VK 与宿主的业务适配；可复用，运行实例和资源仍由各 binding 独占。 */
export class VkAdapter extends MiniAppAdapter<VkHost> {
  readonly vendorId: string = VK_VENDOR_ID;

  constructor(host: VkHost = {}) {
    super({
      createTestBanner: host.createTestBanner,
      createTestNativeAd: host.createTestNativeAd,
      onAuthTokenRequest: host.onAuthTokenRequest,
      onClientMessage: host.onClientMessage,
      onUserInfoRequest: host.onUserInfoRequest
    });
  }

  createNavigationController(): MiniAppNavigationController {
    return new VkNavigationController();
  }

  /** Release 忽略测试工厂，不注册测试接口，也不创建测试 UI。 */
  createTestBanner(): VkTestBannerController | undefined {
    return BuildProfile.DEBUG ? this.host.createTestBanner?.() : undefined;
  }

  createTestNativeAd(): VkTestNativeAdController | undefined {
    return BuildProfile.DEBUG ? this.host.createTestNativeAd?.() : undefined;
  }

  emitClientMessage(fragment?: string): void {
    try {
      this.host.onClientMessage?.(fragment);
    } catch (error) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  async requestUserInfo(request: UserInfoRequest): Promise<UserInfoResult> {
    const handler = this.host.onUserInfoRequest;
    if (!handler) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
    let result: UserInfoResult;
    try {
      result = await handler(request);
    } catch (error) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
    return this.snapshotUserInfo(result);
  }

  hasUserInfoProvider(): boolean {
    return this.host.onUserInfoRequest !== undefined;
  }

  async requestAuthToken(request: AuthTokenRequest): Promise<AuthTokenResult> {
    const handler = this.host.onAuthTokenRequest;
    if (!handler) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
    let result: AuthTokenResult;
    try {
      result = await handler(request);
    } catch (error) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
    if (!result) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
    let accessToken: string;
    let scope: string;
    try {
      accessToken = result.accessToken;
      scope = result.scope;
    } catch (error) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
    if (typeof accessToken !== 'string' || accessToken.length === 0 || typeof scope !== 'string') {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
    return { accessToken, scope };
  }

  private snapshotUserInfo(result: UserInfoResult): UserInfoResult {
    if (!result) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
    let id: number;
    let firstName: string;
    let lastName: string;
    let sex: number;
    let city: UserInfoLocation;
    let cityId: number;
    let cityTitle: string;
    let country: UserInfoLocation;
    let countryId: number;
    let countryTitle: string;
    let birthDate: string | undefined;
    let birthDateVisibility: number;
    let canAccessClosed: boolean;
    let isClosed: boolean;
    let photo100: string;
    let photo200: string;
    let photoMaxOriginal: string | undefined;
    let timezone: number | undefined;
    try {
      id = result.id;
      firstName = result.firstName;
      lastName = result.lastName;
      sex = result.sex;
      city = result.city;
      cityId = city.id;
      cityTitle = city.title;
      country = result.country;
      countryId = country.id;
      countryTitle = country.title;
      birthDate = result.birthDate;
      birthDateVisibility = result.birthDateVisibility;
      canAccessClosed = result.canAccessClosed;
      isClosed = result.isClosed;
      photo100 = result.photo100;
      photo200 = result.photo200;
      photoMaxOriginal = result.photoMaxOriginal;
      timezone = result.timezone;
    } catch (error) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
    if (!Number.isSafeInteger(id) || id <= 0 || typeof firstName !== 'string' ||
      typeof lastName !== 'string' || !Number.isSafeInteger(sex) || sex < 0 || sex > 2 ||
      !Number.isSafeInteger(cityId) || cityId < 0 || typeof cityTitle !== 'string' ||
      !Number.isSafeInteger(countryId) || countryId < 0 || typeof countryTitle !== 'string' ||
      (birthDate !== undefined && typeof birthDate !== 'string') ||
      !Number.isSafeInteger(birthDateVisibility) || birthDateVisibility < 0 || birthDateVisibility > 2 ||
      typeof canAccessClosed !== 'boolean' || typeof isClosed !== 'boolean' ||
      typeof photo100 !== 'string' || photo100.length === 0 ||
      typeof photo200 !== 'string' || photo200.length === 0 ||
      (photoMaxOriginal !== undefined && typeof photoMaxOriginal !== 'string') ||
      (timezone !== undefined && (typeof timezone !== 'number' || !Number.isFinite(timezone)))) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
    const snapshot: UserInfoResult = {
      id,
      firstName,
      lastName,
      sex,
      city: { id: cityId, title: cityTitle },
      country: { id: countryId, title: countryTitle },
      birthDateVisibility,
      canAccessClosed,
      isClosed,
      photo100,
      photo200
    };
    if (birthDate !== undefined) {
      snapshot.birthDate = birthDate;
    }
    if (photoMaxOriginal !== undefined) {
      snapshot.photoMaxOriginal = photoMaxOriginal;
    }
    if (timezone !== undefined) {
      snapshot.timezone = timezone;
    }
    return snapshot;
  }
}
