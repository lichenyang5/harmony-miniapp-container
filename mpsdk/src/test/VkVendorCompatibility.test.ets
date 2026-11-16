import {
  AuthTokenRequest,
  AuthTokenResult,
  UserInfoRequest,
  UserInfoResult,
  VkAdapter
} from '../main/ets/vendors/vk/VkAdapter';
import { VK_VENDOR_ID } from '../main/ets/vendors/vk/VkVendor';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { INVALID_ARGUMENT } from '../main/ets/core/MiniAppErrorCode';
import { TestVendorAdapter } from './TestVendorAdapter';
import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import { BridgeContext, VendorBinding } from '../main/ets/core/Runtime';
import { VkBridgeProxy } from '../main/ets/vendors/vk/VkBridgeProxy';
import { getTestUiAbilityContext, VkTestSession } from './TestContext';

class VendorTestContext implements BridgeContext {
  readonly id: string = 'vendor-compatibility-test';
  readonly appId: string = '54769936';
  readonly vendorId: string = VK_VENDOR_ID;
  readonly uiAbilityContext: common.UIAbilityContext = getTestUiAbilityContext();

  send(_script: string): Promise<boolean> {
    return Promise.resolve(true);
  }

  getDocumentId(): number {
    return 1;
  }

  addCleanup(_cleanup: () => void): void {
  }

  closeMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  openMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  pauseAllMedia(): void {
  }

  setSwipeBackEnabled(_enabled: boolean): void {
  }
}

class UserInfoVendorTestContext extends VendorTestContext {
  requestUserInfo(_request: UserInfoRequest): Promise<UserInfoResult> {
    const result: UserInfoResult = {
      id: 1,
      firstName: 'Test',
      lastName: 'User',
      sex: 0,
      city: { id: 0, title: '' },
      country: { id: 0, title: '' },
      birthDateVisibility: 0,
      canAccessClosed: true,
      isClosed: false,
      photo100: 'https://vk.ru/photo-100.jpg',
      photo200: 'https://vk.ru/photo-200.jpg'
    };
    return Promise.resolve(result);
  }
}

export default function vkVendorCompatibilityTest(): void {
  describe('VkVendorCompatibility', () => {
    it('keepsRemoteSupportedHandlersWithinTheirSessionAndDocument', 0, () => {
      const adapter: VkAdapter = new VkAdapter();
      const session: VkTestSession = new VkTestSession(adapter);
      const sibling: VkTestSession = new VkTestSession(adapter);
      try {
        const proxy: VkBridgeProxy = session.getBinding().injections[0].object as VkBridgeProxy;
        const other: VkBridgeProxy = sibling.getBinding().injections[0].object as VkBridgeProxy;
        expect(proxy.supportedHandlers().indexOf('VKWebAppInit') >= 0).assertTrue();
        proxy.onInterceptResponse(
          '{"type":"SetSupportedHandlers","data":{"supportedHandlers":["Official"]}}');
        expect(proxy.supportedHandlers().indexOf('Official') >= 0).assertTrue();
        expect(other.supportedHandlers().indexOf('Official') < 0).assertTrue();
        session.beginDocument('https://vk.ru/app1?next');
        expect(proxy.supportedHandlers().indexOf('Official') < 0).assertTrue();
        expect(proxy.supportedHandlers().indexOf('VKWebAppInit') >= 0).assertTrue();
        expect(proxy.supportedHandlers().indexOf('VKWebAppOpenContacts') >= 0).assertTrue();
        session.close();
        expect(proxy.supportedHandlers().length).assertEqual(0);
      } finally {
        session.close();
        sibling.close();
      }
    });

    it('rejectsAnAdapterWithOnlyTheMatchingVendorId', 0, () => {
      let errorCode: string = '';
      try {
        new VkTestSession(new TestVendorAdapter(VK_VENDOR_ID));
      } catch (error) {
        errorCode = (error as MiniAppError).code;
      }
      expect(errorCode).assertEqual(INVALID_ARGUMENT);
    });

    it('advertisesAllRegisteredNativeHandlersTogether', 0, () => {
      const session: VkTestSession = new VkTestSession(new VkAdapter({
        onUserInfoRequest: (request: UserInfoRequest): Promise<UserInfoResult> =>
        new UserInfoVendorTestContext().requestUserInfo(request)
      }));
      const binding: VendorBinding = session.getBinding();
      const proxy: VkBridgeProxy = binding.injections[0].object as VkBridgeProxy;
      const result = proxy.onInterceptResponse(
        '{"type":"SetSupportedHandlers","data":{"supportedHandlers":["VKWebAppFlashSetLevel"]}}');
      const event = result.data as Record<string, Object>;
      const data = event['data'] as Record<string, Object>;
      const handlers = data['supportedHandlers'] as string[];

      expect(handlers.indexOf('VKWebAppTapticImpactOccurred') >= 0).assertTrue();
      expect(handlers.indexOf('VKWebAppFlashGetInfo') >= 0).assertTrue();
      expect(handlers.indexOf('VKWebAppFlashSetLevel') >= 0).assertTrue();
      expect(handlers.indexOf('VKWebAppGetGrantedPermissions') >= 0).assertTrue();
      expect(handlers.indexOf('VKWebAppSetViewSettings') >= 0).assertTrue();
      expect(handlers.indexOf('VKWebAppAudioPause') >= 0).assertTrue();
      expect(handlers.indexOf('VKWebAppSendToClient') >= 0).assertTrue();
      expect(handlers.indexOf('VKWebAppSetSwipeSettings') >= 0).assertTrue();
      expect(handlers.indexOf('VKWebAppGetAuthToken') < 0).assertTrue();
      expect(handlers.indexOf('VKWebAppGetUserInfo') >= 0).assertTrue();
      let flashSetLevelCount: number = 0;
      let sendToClientCount: number = 0;
      let setSwipeSettingsCount: number = 0;
      let getAuthTokenCount: number = 0;
      let getUserInfoCount: number = 0;
      handlers.forEach((method: string): void => {
        if (method === 'VKWebAppFlashSetLevel') {
          flashSetLevelCount++;
        }
        if (method === 'VKWebAppSendToClient') {
          sendToClientCount++;
        }
        if (method === 'VKWebAppSetSwipeSettings') {
          setSwipeSettingsCount++;
        }
        if (method === 'VKWebAppGetAuthToken') {
          getAuthTokenCount++;
        }
        if (method === 'VKWebAppGetUserInfo') {
          getUserInfoCount++;
        }
      });
      expect(flashSetLevelCount).assertEqual(1);
      expect(sendToClientCount).assertEqual(1);
      expect(setSwipeSettingsCount).assertEqual(1);
      expect(getAuthTokenCount).assertEqual(0);
      expect(getUserInfoCount).assertEqual(1);
      session.close();
    });

    it('passesThroughWebAuthAndUserInfoWhenHostProvidersAreMissing', 0, () => {
      const session: VkTestSession = new VkTestSession(new VkAdapter());
      const binding: VendorBinding = session.getBinding();
      const proxy: VkBridgeProxy = binding.injections[0].object as VkBridgeProxy;

      const result = proxy.onInterceptRequest(
        '{"type":"vk-connect","handler":"VKWebAppGetUserInfo","params":{},"request_id":"user-info-1"}',
        'reply-user-info-1');
      const authResult = proxy.onInterceptRequest(
        '{"type":"vk-connect","handler":"VKWebAppGetAuthToken",' +
          '"params":{"app_id":54769936,"scope":""},"request_id":"auth-web-1"}',
        'reply-auth-web-1');
      const supportedResult = proxy.onInterceptResponse(
        '{"type":"SetSupportedHandlers","data":{"supportedHandlers":[]}}');
      const event = supportedResult.data as Record<string, Object>;
      const data = event['data'] as Record<string, Object>;
      const handlers = data['supportedHandlers'] as string[];

      expect(result.intercept).assertFalse();
      expect(authResult.intercept).assertFalse();
      expect(handlers.indexOf('VKWebAppGetUserInfo') >= 0).assertTrue();
      expect(handlers.indexOf('VKWebAppGetAuthToken') < 0).assertTrue();
      session.close();
    });

    it('keepsWebAuthAndUserInfoEvenWhenHostProvidersAreConfigured', 0, async () => {
      let authCalls: number = 0;
      let userCalls: number = 0;
      const session: VkTestSession = new VkTestSession(new VkAdapter({
        onAuthTokenRequest: (_request: AuthTokenRequest): Promise<AuthTokenResult> => {
          authCalls++;
          return Promise.reject(new Error('Web 透传不应调用宿主授权'));
        },
        onUserInfoRequest: (_request: UserInfoRequest): Promise<UserInfoResult> => {
          userCalls++;
          return Promise.reject(new Error('Web 透传不应调用宿主用户资料'));
        }
      }));
      const binding: VendorBinding = session.getBinding();
      const proxy: VkBridgeProxy = binding.injections[0].object as VkBridgeProxy;
      const authResult = proxy.onInterceptRequest(
        '{"type":"vk-connect","handler":"VKWebAppGetAuthToken",' +
          '"params":{"app_id":54769936,"scope":""},"request_id":"auth-web-2"}', 'reply-auth-web-2');
      const userResult = proxy.onInterceptRequest(
        '{"type":"vk-connect","handler":"VKWebAppGetUserInfo","params":{},"request_id":"user-web-2"}',
        'reply-user-web-2');
      const supportedResult = proxy.onInterceptResponse(
        '{"type":"SetSupportedHandlers","data":' +
          '{"supportedHandlers":["VKWebAppGetAuthToken","VKWebAppGetUserInfo"]}}');
      const event = supportedResult.data as Record<string, Object>;
      const data = event['data'] as Record<string, Object>;
      const handlers = data['supportedHandlers'] as string[];

      await Promise.resolve();
      expect(authResult.intercept).assertFalse();
      expect(userResult.intercept).assertFalse();
      expect(authCalls).assertEqual(0);
      expect(userCalls).assertEqual(0);
      expect(handlers.filter((method: string): boolean => method === 'VKWebAppGetAuthToken').length).assertEqual(1);
      expect(handlers.filter((method: string): boolean => method === 'VKWebAppGetUserInfo').length).assertEqual(1);
      expect(proxy.onInterceptResponse(
        '{"type":"VKWebAppAccessTokenFailed","data":' +
          '{"error_type":"client_error","error_data":{"error_code":4,"error_reason":"User denied"}}}'
      ).intercept).assertFalse();
      expect(proxy.onInterceptResponse(
        '{"type":"VKWebAppGetUserInfoResult","data":{"id":1}}'
      ).intercept).assertFalse();
      session.close();
    });
  });
}
