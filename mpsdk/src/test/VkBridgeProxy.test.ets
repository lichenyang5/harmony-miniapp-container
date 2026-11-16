import { VkBridgeError } from '../main/ets/vendors/vk/VkBridgeError';
import { VkClientErrorCode } from '../main/ets/vendors/vk/VkClientErrorCode';
import {
  AuthTokenRequest,
  AuthTokenRequestHandler,
  AuthTokenResult,
  UserInfoRequest,
  UserInfoRequestHandler,
  UserInfoResult,
  VkAdapter
} from '../main/ets/vendors/vk/VkAdapter';
import { describe, expect, it } from '@ohos/hypium';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { SYSTEM_ERROR } from '../main/ets/core/MiniAppErrorCode';
import {
  BridgeContext,
  DocumentScript,
  MiniAppDescriptor,
  MiniAppSession,
  SwipeBackController,
  VendorBinding,
  WebEndpoint,
  WebLoadRequest
} from '../main/ets/core/Runtime';
import { BaseVkEventHandler } from '../main/ets/vendors/vk/events/BaseVkEventHandler';
import { VkEvent } from '../main/ets/vendors/vk/events/VkEvent';
import { VkEventRegistry } from '../main/ets/vendors/vk/events/VkEventRegistry';
import { VkBridgeProxy } from '../main/ets/vendors/vk/VkBridgeProxy';
import { VkAudioHandler } from '../main/ets/vendors/vk/handlers/VkAudioHandler';
import { VkClientMessageHandler } from '../main/ets/vendors/vk/handlers/VkClientMessageHandler';
import { VK_VENDOR_ID, VkVendor } from '../main/ets/vendors/vk/VkVendor';
import { getTestUiAbilityContext, VkTestSession } from './TestContext';

class TestBridgeContext extends VkTestSession {
  scripts: string[] = [];
  failMediaPause: boolean = false;
  failClientMessage: boolean = false;

  send(script: string): Promise<boolean> {
    this.scripts.push(script);
    return Promise.resolve(true);
  }

  closeMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  openMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  pauseAllMedia(): void {
    if (this.failMediaPause) {
      throw new Error('暂停网页媒体失败');
    }
  }

  recordClientMessage(_fragment?: string): void {
    if (this.failClientMessage) {
      throw new MiniAppError(SYSTEM_ERROR, '宿主处理客户端消息失败');
    }
  }

  setSwipeBackEnabled(_enabled: boolean): void {
  }
}

class ProxyNoopSwipeBackController implements SwipeBackController {
  setEnabled(_enabled: boolean): void {
  }

  dispose(): void {
  }
}

class RecordingWebEndpoint implements WebEndpoint {
  scripts: string[] = [];

  evaluate(script: string): Promise<string> {
    this.scripts.push(script);
    return Promise.resolve('');
  }

  pauseAllMedia(): void {
  }

  load(_request: WebLoadRequest, _scripts: DocumentScript[]): Promise<void> {
    return Promise.resolve();
  }
}

interface AuthProxyFixture {
  session: MiniAppSession;
  proxy: VkBridgeProxy;
  endpoint: RecordingWebEndpoint;
}

function createAuthProxy(handler: AuthTokenRequestHandler): AuthProxyFixture {
  const descriptor: MiniAppDescriptor = {
    info: { appId: '54769936', vendor: VK_VENDOR_ID, url: 'https://vk.ru/app54769936' },
    vendor: new VkVendor(),
    adapter: new VkAdapter({ onAuthTokenRequest: handler }),
    swipeBackController: new ProxyNoopSwipeBackController()
  };
  const session: MiniAppSession = new MiniAppSession(
    'auth-proxy-session', descriptor, getTestUiAbilityContext());
  const endpoint: RecordingWebEndpoint = new RecordingWebEndpoint();
  session.attach(endpoint);
  const binding: VendorBinding = session.getBinding();
  return {
    session,
    proxy: binding.injections[0].object as VkBridgeProxy,
    endpoint
  };
}

function createUserInfoResult(): UserInfoResult {
  return {
    id: 2314852,
    firstName: 'Irina',
    lastName: 'Denezhkina',
    sex: 1,
    city: { id: 2, title: 'Saint Petersburg' },
    country: { id: 1, title: 'Russia' },
    birthDate: '10.4.1990',
    birthDateVisibility: 1,
    canAccessClosed: true,
    isClosed: false,
    photo100: 'https://vk.ru/photo-100.jpg',
    photo200: 'https://vk.ru/photo-200.jpg',
    photoMaxOriginal: 'https://vk.ru/photo-max.jpg',
    timezone: 3
  };
}

function createUserInfoProxy(handler: UserInfoRequestHandler): AuthProxyFixture {
  const descriptor: MiniAppDescriptor = {
    info: { appId: 'host-business-id', vendor: VK_VENDOR_ID, url: 'https://vk.ru/app54769936' },
    vendor: new VkVendor(),
    adapter: new VkAdapter({ onUserInfoRequest: handler }),
    swipeBackController: new ProxyNoopSwipeBackController()
  };
  const session: MiniAppSession = new MiniAppSession(
    'user-info-proxy-session', descriptor, getTestUiAbilityContext());
  const endpoint: RecordingWebEndpoint = new RecordingWebEndpoint();
  session.attach(endpoint);
  const binding: VendorBinding = session.getBinding();
  return {
    session,
    proxy: binding.injections[0].object as VkBridgeProxy,
    endpoint
  };
}

async function flushAuthDispatch(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

class TestHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: 'VKWebAppTestNative' })
  testNative(_params: object): Promise<object> {
    return Promise.resolve(JSON.parse('{"result":true}') as object);
  }

  @VkEvent({ name: 'VKWebAppTestNoTimeout', timeout: 0 })
  testNoTimeout(_params: object): Promise<object> {
    return Promise.resolve(JSON.parse('{"result":true}') as object);
  }

  dispose(): void {
  }
}

class FailingHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: 'VKWebAppTestFailure' })
  testFailure(_params: object): Promise<object> {
    return Promise.reject(VkBridgeError.client(VkClientErrorCode.INVALID_PARAMS));
  }

  dispose(): void {
  }
}

export default function vkBridgeProxyTest(): void {
  describe('VkBridgeProxy', () => {
    it('keepsPublicProxyAndDelegatesMatchedRequest', 0, async () => {
      const context = new TestBridgeContext();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new TestHandler(context)]);
      const proxy = new VkBridgeProxy(context, registry);

      const result = proxy.onInterceptRequest(
        '{"type":"vk-connect","handler":"VKWebAppTestNative",' +
          '"params":{"request_id":"1_test"}}', 'reply-1');
      await Promise.resolve();

      expect(result.intercept).assertTrue();
      expect(result.timeout).assertEqual(30000);
      expect(context.scripts.length).assertEqual(1);
      expect(context.scripts[0]).assertContain('VKWebAppTestNativeResult');
      expect(context.scripts[0]).assertContain('1_test');
      proxy.dispose();
      registry.dispose();
      context.close();
    });

    it('returnsZeroTimeoutForNoTimeoutEvent', 0, () => {
      const context = new TestBridgeContext();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new TestHandler(context)]);
      const proxy = new VkBridgeProxy(context, registry);

      const result = proxy.onInterceptRequest(
        '{"type":"vk-connect","handler":"VKWebAppTestNoTimeout",' +
          '"params":{"request_id":"no-timeout"}}', 'reply-no-timeout');

      expect(result.intercept).assertTrue();
      expect(result.timeout).assertEqual(0);
      proxy.dispose();
      registry.dispose();
      context.close();
    });

    it('passesRequestWhenNoModuleSupportsIt', 0, () => {
      const context = new TestBridgeContext();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new TestHandler(context)]);
      const proxy = new VkBridgeProxy(context, registry);
      const result = proxy.onInterceptRequest(
        '{"type":"vk-connect","handler":"VKWebAppUnknown","params":{}}', 'reply-2');

      expect(result.intercept).assertFalse();
      proxy.dispose();
      registry.dispose();
      context.close();
    });

    it('returnsFailureEnvelopeAndPreservesRequestId', 0, async () => {
      const context = new TestBridgeContext();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new FailingHandler(context)]);
      const proxy = new VkBridgeProxy(context, registry);

      const result = proxy.onInterceptRequest(
        '{"type":"vk-connect","handler":"VKWebAppTestFailure",' +
          '"params":{"request_id":"3_test"}}', 'reply-3');
      await Promise.resolve();

      expect(result.intercept).assertTrue();
      expect(context.scripts.length).assertEqual(1);
      expect(context.scripts[0]).assertContain('VKWebAppTestFailureFailed');
      expect(context.scripts[0]).assertContain('3_test');
      expect(context.scripts[0]).assertContain('Invalid params');
      proxy.dispose();
      registry.dispose();
      context.close();
    });

    it('returnsAudioPauseFailureEnvelopeAndPreservesRequestId', 0, async () => {
      const context: TestBridgeContext = new TestBridgeContext();
      context.failMediaPause = true;
      const registry = new VkEventRegistry(context);
      registry.initHandler([new VkAudioHandler(context)]);
      const proxy: VkBridgeProxy = new VkBridgeProxy(context, registry);

      const result = proxy.onInterceptRequest(
        '{"type":"vk-connect","handler":"VKWebAppAudioPause",' +
          '"params":{"request_id":"4_audio"}}', 'reply-audio');
      await Promise.resolve();
      await Promise.resolve();

      expect(result.intercept).assertTrue();
      expect(context.scripts.length).assertEqual(1);
      expect(context.scripts[0]).assertContain('VKWebAppAudioPauseFailed');
      expect(context.scripts[0]).assertContain('4_audio');
      expect(context.scripts[0]).assertContain('Unknown error');
      proxy.dispose();
      registry.dispose();
      context.close();
    });

    it('returnsClientMessageFailureEnvelopeAndPreservesRequestId', 0, async () => {
      const context: TestBridgeContext = new TestBridgeContext();
      context.failClientMessage = true;
      const registry = new VkEventRegistry(context);
      registry.initHandler([new VkClientMessageHandler(context, new VkAdapter({
        onClientMessage: (fragment?: string): void => context.recordClientMessage(fragment)
      }))]);
      const proxy: VkBridgeProxy = new VkBridgeProxy(context, registry);

      const result = proxy.onInterceptRequest(
        '{"type":"vk-connect","handler":"VKWebAppSendToClient",' +
          '"params":{"fragment":"example","request_id":"send_1"}}', 'reply-client-message');
      await Promise.resolve();
      await Promise.resolve();

      expect(result.intercept).assertTrue();
      expect(context.scripts.length).assertEqual(1);
      expect(context.scripts[0]).assertContain('VKWebAppSendToClientFailed');
      expect(context.scripts[0]).assertContain('send_1');
      expect(context.scripts[0]).assertContain('Unknown error');
      proxy.dispose();
      registry.dispose();
      context.close();
    });

    it('passesAuthRequestsToWebWithoutCallingSuccessfulHostProvider', 0, async () => {
      let calls: number = 0;
      const fixture: AuthProxyFixture = createAuthProxy(
        async (request: AuthTokenRequest): Promise<AuthTokenResult> => {
          calls++;
          return { accessToken: 'host-token', scope: request.scope };
        });
      try {
        const result = fixture.proxy.onInterceptRequest(
          '{"type":"vk-connect","handler":"VKWebAppGetAuthToken",' +
            '"params":{"app_id":54769936,"scope":"friends","request_id":"auth_1"}}', 'reply-auth');
        await flushAuthDispatch();
        expect(result.intercept).assertFalse();
        expect(calls).assertEqual(0);
        expect(fixture.endpoint.scripts.length).assertEqual(0);
      } finally {
        fixture.session.close();
      }
    });

    it('passesAuthRequestsToWebWithoutCallingFailingHostProvider', 0, async () => {
      let calls: number = 0;
      const fixture: AuthProxyFixture = createAuthProxy(
        async (_request: AuthTokenRequest): Promise<AuthTokenResult> => {
          calls++;
          throw new MiniAppError('HOST_PRIVATE_ERROR', 'backend secret: token-value');
        });
      try {
        const result = fixture.proxy.onInterceptRequest(
          '{"type":"vk-connect","handler":"VKWebAppGetAuthToken",' +
            '"params":{"app_id":54769936,"scope":"friends","request_id":"auth_2"}}', 'reply-auth-fail');
        await flushAuthDispatch();
        expect(result.intercept).assertFalse();
        expect(calls).assertEqual(0);
        expect(fixture.endpoint.scripts.length).assertEqual(0);
      } finally {
        fixture.session.close();
      }
    });

    it('passesUserInfoRequestsToWebWithoutCallingSuccessfulHostProvider', 0, async () => {
      let calls: number = 0;
      const fixture: AuthProxyFixture = createUserInfoProxy(
        async (_request: UserInfoRequest): Promise<UserInfoResult> => {
          calls++;
          return createUserInfoResult();
        });
      try {
        const result = fixture.proxy.onInterceptRequest(
          '{"type":"vk-connect","handler":"VKWebAppGetUserInfo",' +
            '"params":{"user_id":2314852,"request_id":"user_1"}}', 'reply-user-info');
        await flushAuthDispatch();
        expect(result.intercept).assertFalse();
        expect(calls).assertEqual(0);
        expect(fixture.endpoint.scripts.length).assertEqual(0);
      } finally {
        fixture.session.close();
      }
    });

    it('passesUserInfoRequestsToWebWithoutCallingFailingHostProvider', 0, async () => {
      let calls: number = 0;
      const fixture: AuthProxyFixture = createUserInfoProxy(
        async (_request: UserInfoRequest): Promise<UserInfoResult> => {
          calls++;
          throw new MiniAppError('HOST_PRIVATE_ERROR', 'backend secret: user-profile');
        });
      try {
        const result = fixture.proxy.onInterceptRequest(
          '{"type":"vk-connect","handler":"VKWebAppGetUserInfo",' +
            '"params":{"request_id":"user_2"}}', 'reply-user-info-fail');
        await flushAuthDispatch();
        expect(result.intercept).assertFalse();
        expect(calls).assertEqual(0);
        expect(fixture.endpoint.scripts.length).assertEqual(0);
      } finally {
        fixture.session.close();
      }
    });

    it('passesOfficialAuthResponsesThroughWithoutRewriting', 0, () => {
      const session: VkTestSession = new VkTestSession();
      try {
        const proxy: VkBridgeProxy = session.getBinding().injections[0].object as VkBridgeProxy;
        const responses: string[] = [
          '{"type":"VKWebAppAccessTokenReceived","data":{"access_token":"web-token","scope":"friends","request_id":"auth"}}',
          '{"type":"VKWebAppAccessTokenFailed","data":{"error_type":"client_error","error_data":{"error_code":4,"error_reason":"User denied"},"request_id":"auth"}}'
        ];
        responses.forEach((response: string): void => {
          const result = proxy.onInterceptResponse(response);
          expect(result.intercept).assertFalse();
          expect(result.data).assertUndefined();
        });
      } finally {
        session.close();
      }
    });

    it('passesOfficialUserInfoResponsesThroughWithoutRewriting', 0, () => {
      const session: VkTestSession = new VkTestSession();
      try {
        const proxy: VkBridgeProxy = session.getBinding().injections[0].object as VkBridgeProxy;
        const responses: string[] = [
          '{"type":"VKWebAppGetUserInfoResult","data":{"id":2314852,"first_name":"Irina","request_id":"user"}}',
          '{"type":"VKWebAppGetUserInfoFailed","data":{"error_type":"client_error","error_data":{"error_code":1,"error_reason":"Unknown error"},"request_id":"user"}}'
        ];
        responses.forEach((response: string): void => {
          const result = proxy.onInterceptResponse(response);
          expect(result.intercept).assertFalse();
          expect(result.data).assertUndefined();
        });
      } finally {
        session.close();
      }
    });
  });
}
