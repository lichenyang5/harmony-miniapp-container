import { vkClientCode } from './VkErrorTestUtils';
import { describe, expect, it } from '@ohos/hypium';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import {
  UserInfoLocation,
  UserInfoRequest,
  UserInfoRequestHandler,
  UserInfoResult,
  VkAdapter
} from '../main/ets/vendors/vk/VkAdapter';

class ThrowingUserInfoResult implements UserInfoResult {
  readonly id: number = 2314852;
  readonly lastName: string = 'Denezhkina';
  readonly sex: number = 1;
  readonly city: UserInfoLocation = { id: 2, title: 'Saint Petersburg' };
  readonly country: UserInfoLocation = { id: 1, title: 'Russia' };
  readonly birthDateVisibility: number = 1;
  readonly canAccessClosed: boolean = true;
  readonly isClosed: boolean = false;
  readonly photo100: string = 'https://vk.ru/photo-100.jpg';
  readonly photo200: string = 'https://vk.ru/photo-200.jpg';

  get firstName(): string {
    throw new MiniAppError('HOST_PRIVATE_ERROR', 'backend secret: user-profile');
  }
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

function createUserInfoAdapter(_id: string, handler?: UserInfoRequestHandler): VkAdapter {
  return new VkAdapter({ onUserInfoRequest: handler });
}

async function captureError(operation: Promise<UserInfoResult>): Promise<MiniAppError | undefined> {
  try {
    await operation;
  } catch (error) {
    return error as MiniAppError;
  }
  return undefined;
}

export default function vkAdapterUserInfoTest(): void {
  describe('VkAdapterUserInfo', () => {
    it('forwardsRequestAndReturnsDetachedValidatedSnapshot', 0, async () => {
      let received: UserInfoRequest | undefined;
      const hostResult: UserInfoResult = createUserInfoResult();
      const session: VkAdapter = createUserInfoAdapter(
        'user-info-success', async (request: UserInfoRequest): Promise<UserInfoResult> => {
        received = request;
        return hostResult;
      });

      const result: UserInfoResult = await session.requestUserInfo({ userId: 2314852, userIds: '2314852' });
      hostResult.city.title = 'Changed';
      hostResult.country.title = 'Changed';

      expect(received?.userId).assertEqual(2314852);
      expect(received?.userIds).assertEqual('2314852');
      expect(result.firstName).assertEqual('Irina');
      expect(result.city.title).assertEqual('Saint Petersburg');
      expect(result.country.title).assertEqual('Russia');
      expect(result.photoMaxOriginal).assertEqual('https://vk.ru/photo-max.jpg');
    });

    it('rejectsInvalidHostProfile', 0, async () => {
      const session: VkAdapter = createUserInfoAdapter(
        'user-info-invalid', async (_request: UserInfoRequest): Promise<UserInfoResult> => {
        const invalid = createUserInfoResult();
        invalid.photo100 = '';
        return invalid;
      });

      const failure = await captureError(session.requestUserInfo({}));

      expect(vkClientCode(failure)).assertEqual('1');
      expect(failure?.message).assertEqual('client_error: {"error_code":1,"error_reason":"Unknown error"}');
    });

    it('sanitizesHostProfileGetterFailures', 0, async () => {
      const session: VkAdapter = createUserInfoAdapter(
        'user-info-getter-failure', async (_request: UserInfoRequest): Promise<UserInfoResult> => {
        return new ThrowingUserInfoResult();
      });

      const failure = await captureError(session.requestUserInfo({}));
      const failureMessage: string = failure?.message ?? '';

      expect(vkClientCode(failure)).assertEqual('1');
      expect(failure?.message).assertEqual('client_error: {"error_code":1,"error_reason":"Unknown error"}');
      expect(failureMessage.indexOf('backend secret') < 0).assertTrue();
      expect(failureMessage.indexOf('user-profile') < 0).assertTrue();
    });

    it('sanitizesHostFailuresBeforeTheyReachTheWebLayer', 0, async () => {
      const session: VkAdapter = createUserInfoAdapter(
        'user-info-failure', async (_request: UserInfoRequest): Promise<UserInfoResult> => {
        throw new MiniAppError('HOST_PRIVATE_ERROR', 'backend secret: user-profile');
      });

      const failure = await captureError(session.requestUserInfo({}));

      expect(vkClientCode(failure)).assertEqual('1');
      expect(failure?.message).assertEqual('client_error: {"error_code":1,"error_reason":"Unknown error"}');
    });

    it('reportsUnknownWhenHostCallbackIsMissing', 0, async () => {
      const session: VkAdapter = createUserInfoAdapter('user-info-missing');

      const failure = await captureError(session.requestUserInfo({}));

      expect(vkClientCode(failure)).assertEqual('1');
    });

  });
}
