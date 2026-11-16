import { vkClientCode } from './VkErrorTestUtils';
import { describe, expect, it } from '@ohos/hypium';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { AuthTokenRequest, AuthTokenResult, VkAdapter } from '../main/ets/vendors/vk/VkAdapter';

class ChangingAuthTokenResult implements AuthTokenResult {
  readonly scope: string = 'friends';
  private readCount: number = 0;

  get accessToken(): string {
    this.readCount++;
    return this.readCount === 1 ? 'snapshot-token' : 'changed-token';
  }
}

class ThrowingAuthTokenResult implements AuthTokenResult {
  readonly scope: string = 'friends';

  get accessToken(): string {
    throw new MiniAppError('HOST_PRIVATE_ERROR', 'backend secret: token-value');
  }
}

async function captureErrorCode(operation: Promise<AuthTokenResult>): Promise<string> {
  try {
    await operation;
  } catch (error) {
    return vkClientCode(error as Object);
  }
  return '';
}

export default function vkAdapterAuthTokenTest(): void {
  describe('VkAdapterAuthToken', () => {
    it('forwardsRequestToOwningHostAndReturnsValidatedResult', 0, async () => {
      let received: AuthTokenRequest | undefined;
      const adapter: VkAdapter = new VkAdapter({
        onAuthTokenRequest: async (request: AuthTokenRequest): Promise<AuthTokenResult> => {
          received = request;
          return { accessToken: 'token-one', scope: 'friends,photos' };
        }
      });

      const result: AuthTokenResult = await adapter.requestAuthToken({
        appId: 54769936,
        scope: 'friends,photos'
      });

      expect(received?.appId).assertEqual(54769936);
      expect(received?.scope).assertEqual('friends,photos');
      expect(result.accessToken).assertEqual('token-one');
      expect(result.scope).assertEqual('friends,photos');
    });

    it('keepsAuthProvidersIsolatedBetweenAdapters', 0, async () => {
      const first: VkAdapter = new VkAdapter({
        onAuthTokenRequest: async (_request: AuthTokenRequest): Promise<AuthTokenResult> => {
          return { accessToken: 'first-token', scope: 'friends' };
        }
      });
      const second: VkAdapter = new VkAdapter({
        onAuthTokenRequest: async (_request: AuthTokenRequest): Promise<AuthTokenResult> => {
          return { accessToken: 'second-token', scope: 'photos' };
        }
      });

      const firstResult = await first.requestAuthToken({ appId: 54769936, scope: 'friends' });
      const secondResult = await second.requestAuthToken({ appId: 54769936, scope: 'photos' });

      expect(firstResult.accessToken).assertEqual('first-token');
      expect(secondResult.accessToken).assertEqual('second-token');
    });

    it('rejectsInvalidHostResultWithoutReturningEmptyToken', 0, async () => {
      const adapter: VkAdapter = new VkAdapter({
        onAuthTokenRequest: async (_request: AuthTokenRequest): Promise<AuthTokenResult> => {
          return { accessToken: '', scope: 'friends' };
        }
      });

      const errorCode: string = await captureErrorCode(
        adapter.requestAuthToken({ appId: 54769936, scope: 'friends' }));

      expect(errorCode).assertEqual('1');
    });

    it('snapshotsHostResultPropertiesBeforeReturningThem', 0, async () => {
      const adapter: VkAdapter = new VkAdapter({
        onAuthTokenRequest: async (_request: AuthTokenRequest): Promise<AuthTokenResult> => {
          return new ChangingAuthTokenResult();
        }
      });

      const result: AuthTokenResult = await adapter.requestAuthToken({
        appId: 54769936,
        scope: 'friends'
      });

      expect(result.accessToken).assertEqual('snapshot-token');
      expect(result.scope).assertEqual('friends');
    });

    it('sanitizesHostResultPropertyFailures', 0, async () => {
      const adapter: VkAdapter = new VkAdapter({
        onAuthTokenRequest: async (_request: AuthTokenRequest): Promise<AuthTokenResult> => {
          return new ThrowingAuthTokenResult();
        }
      });
      let failure: MiniAppError | undefined;

      try {
        await adapter.requestAuthToken({ appId: 54769936, scope: 'friends' });
      } catch (error) {
        failure = error as MiniAppError;
      }

      expect(vkClientCode(failure)).assertEqual('1');
      expect(failure?.message).assertEqual('client_error: {"error_code":1,"error_reason":"Unknown error"}');
    });

    it('wrapsOrdinaryHostFailuresAsVkUnknownErrors', 0, async () => {
      const adapter: VkAdapter = new VkAdapter({
        onAuthTokenRequest: async (_request: AuthTokenRequest): Promise<AuthTokenResult> => {
          throw new Error('host auth failed');
        }
      });

      const errorCode: string = await captureErrorCode(
        adapter.requestAuthToken({ appId: 54769936, scope: 'friends' }));

      expect(errorCode).assertEqual('1');
    });

    it('sanitizesHostMiniAppErrorsBeforeTheyReachTheWebLayer', 0, async () => {
      const adapter: VkAdapter = new VkAdapter({
        onAuthTokenRequest: async (_request: AuthTokenRequest): Promise<AuthTokenResult> => {
          throw new MiniAppError('HOST_PRIVATE_ERROR', 'backend secret: token-value');
        }
      });
      let failure: MiniAppError | undefined;

      try {
        await adapter.requestAuthToken({ appId: 54769936, scope: 'friends' });
      } catch (error) {
        failure = error as MiniAppError;
      }

      expect(vkClientCode(failure)).assertEqual('1');
      expect(failure?.message).assertEqual('client_error: {"error_code":1,"error_reason":"Unknown error"}');
    });

    it('reportsUnknownWhenHostCallbackIsMissing', 0, async () => {
      const adapter: VkAdapter = new VkAdapter();

      const errorCode: string = await captureErrorCode(
        adapter.requestAuthToken({ appId: 54769936, scope: '' }));

      expect(errorCode).assertEqual('1');
    });
  });
}
