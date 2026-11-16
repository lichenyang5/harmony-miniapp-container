import { MiniAppError } from '../main/ets/core/MiniAppError';
import { vkClientCode } from './VkErrorTestUtils';
import { VK_VENDOR_ID } from '../main/ets/vendors/vk/VkVendor';
import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import { BridgeContext } from '../main/ets/core/Runtime';
import { AuthTokenRequest, AuthTokenResult, VkAdapter } from '../main/ets/vendors/vk/VkAdapter';
import {
  VkAuthTokenHandler, VkAuthTokenParams
} from '../main/ets/vendors/vk/handlers/VkAuthTokenHandler';
import { getTestUiAbilityContext } from './TestContext';

class RecordingAuthTokenContext implements BridgeContext {
  readonly id: string = 'auth-token-handler-test';
  readonly appId: string;
  readonly vendorId: string = VK_VENDOR_ID;
  readonly uiAbilityContext: common.UIAbilityContext = getTestUiAbilityContext();
  requests: AuthTokenRequest[] = [];

  constructor(appId: string = '54769936') {
    this.appId = appId;
  }

  send(_script: string): Promise<boolean> {
    return Promise.resolve(true);
  }

  getDocumentId(): number {
    return 1;
  }

  addCleanup(_cleanup: () => void): void {
  }

  openMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  closeMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  pauseAllMedia(): void {
  }

  setSwipeBackEnabled(_enabled: boolean): void {
  }

  recordRequest(request: AuthTokenRequest): Promise<AuthTokenResult> {
    this.requests.push(request);
    const result: AuthTokenResult = { accessToken: 'vk-access-token', scope: request.scope };
    return Promise.resolve(result);
  }
}

async function captureErrorCode(handler: VkAuthTokenHandler, paramsJson: string): Promise<string> {
  try {
    await handler.getAuthToken(JSON.parse(paramsJson) as VkAuthTokenParams);
  } catch (error) {
    return error instanceof MiniAppError && error.code === 'INVALID_ARGUMENT' ? error.code :
      vkClientCode(error as Object);
  }
  return '';
}

export default function vkAuthTokenHandlerTest(): void {
  describe('VkAuthTokenHandler', () => {
    it('rejectsRequestsAfterDisposeWithoutCallingHost', 0, async () => {
      const context: RecordingAuthTokenContext = new RecordingAuthTokenContext();
      const handler: VkAuthTokenHandler = new VkAuthTokenHandler(context, new VkAdapter({
        onAuthTokenRequest: (request: AuthTokenRequest): Promise<AuthTokenResult> => context.recordRequest(request)
      }));
      handler.dispose();

      const errorCode: string = await captureErrorCode(handler, '{"app_id":54769936,"scope":""}');

      expect(errorCode).assertEqual('1');
      expect(context.requests.length).assertEqual(0);
    });

    it('rejectsPendingResultAfterDispose', 0, async () => {
      const context: RecordingAuthTokenContext = new RecordingAuthTokenContext();
      let resolveToken: ((result: AuthTokenResult) => void) | undefined;
      const pending: Promise<AuthTokenResult> = new Promise<AuthTokenResult>((resolve) => {
        resolveToken = resolve;
      });
      const handler: VkAuthTokenHandler = new VkAuthTokenHandler(context, new VkAdapter({
        onAuthTokenRequest: (_request: AuthTokenRequest): Promise<AuthTokenResult> => pending
      }));
      const errorCode: Promise<string> = captureErrorCode(handler, '{"app_id":54769936,"scope":""}');
      handler.dispose();
      if (resolveToken) {
        resolveToken({ accessToken: 'late-token', scope: '' });
      }

      expect(await errorCode).assertEqual('1');
    });

    it('mapsOfficialRequestAndReturnsOfficialTokenFields', 0, async () => {
      const context: RecordingAuthTokenContext = new RecordingAuthTokenContext();
      const handler: VkAuthTokenHandler = new VkAuthTokenHandler(context, new VkAdapter({
        onAuthTokenRequest: (request: AuthTokenRequest): Promise<AuthTokenResult> => context.recordRequest(request)
      }));

      const result = await handler.getAuthToken({ app_id: 54769936, scope: 'friends,photos' });

      expect(context.requests.length).assertEqual(1);
      expect(context.requests[0].appId).assertEqual(54769936);
      expect(context.requests[0].scope).assertEqual('friends,photos');
      expect(result.access_token).assertEqual('vk-access-token');
      expect(result.scope).assertEqual('friends,photos');
    });

    it('allowsEmptyScopeUsedByOfficialBridgeWrapper', 0, async () => {
      const context: RecordingAuthTokenContext = new RecordingAuthTokenContext();
      const handler: VkAuthTokenHandler = new VkAuthTokenHandler(context, new VkAdapter({
        onAuthTokenRequest: (request: AuthTokenRequest): Promise<AuthTokenResult> => context.recordRequest(request)
      }));

      const result = await handler.getAuthToken({ app_id: 54769936, scope: '' });

      expect(context.requests.length).assertEqual(1);
      expect(result.scope).assertEqual('');
    });

    it('acceptsVkAppIdIndependentFromHostBusinessId', 0, async () => {
      const context: RecordingAuthTokenContext =
        new RecordingAuthTokenContext('8f6c0d0c-afc7-498e-9f92-9b75058ad74c');
      const handler: VkAuthTokenHandler = new VkAuthTokenHandler(context, new VkAdapter({
        onAuthTokenRequest: (request: AuthTokenRequest): Promise<AuthTokenResult> => context.recordRequest(request)
      }));

      const result = await handler.getAuthToken({ app_id: 54769936, scope: 'friends' });

      expect(context.requests.length).assertEqual(1);
      expect(context.requests[0].appId).assertEqual(54769936);
      expect(result.access_token).assertEqual('vk-access-token');
    });

    it('rejectsInvalidParameterTypesBeforeCallingHost', 0, async () => {
      const context: RecordingAuthTokenContext = new RecordingAuthTokenContext();
      const handler: VkAuthTokenHandler = new VkAuthTokenHandler(context, new VkAdapter({
        onAuthTokenRequest: (request: AuthTokenRequest): Promise<AuthTokenResult> => context.recordRequest(request)
      }));

      const invalidAppId: string = await captureErrorCode(
        handler, '{"app_id":"54769936","scope":"friends"}');
      const invalidScope: string = await captureErrorCode(
        handler, '{"app_id":54769936,"scope":null}');

      expect(invalidAppId).assertEqual('INVALID_ARGUMENT');
      expect(invalidScope).assertEqual('INVALID_ARGUMENT');
      expect(context.requests.length).assertEqual(0);
    });
  });
}
