import { MiniAppError } from '../main/ets/core/MiniAppError';
import { vkClientCode } from './VkErrorTestUtils';
import { UserInfoRequest, UserInfoResult, VkAdapter } from '../main/ets/vendors/vk/VkAdapter';
import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import { BridgeContext, } from '../main/ets/core/Runtime';
import { VkUserInfoParams, VkUsersHandler } from '../main/ets/vendors/vk/handlers/VkUsersHandler';
import { getTestUiAbilityContext } from './TestContext';

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

class RecordingUserInfoContext implements BridgeContext {
  readonly id: string = 'user-info-handler-test';
  readonly appId: string = 'host-business-id';
  readonly vendorId: string = 'vk';
  readonly uiAbilityContext: common.UIAbilityContext = getTestUiAbilityContext();
  requests: UserInfoRequest[] = [];

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

  emitClientMessage(_fragment?: string): void {
  }

  setSwipeBackEnabled(_enabled: boolean): void {
  }

  requestUserInfo(request: UserInfoRequest): Promise<UserInfoResult> {
    this.requests.push(request);
    return Promise.resolve(createUserInfoResult());
  }
}

async function captureErrorCode(handler: VkUsersHandler, paramsJson: string): Promise<string> {
  try {
    await handler.getUserInfo(JSON.parse(paramsJson) as VkUserInfoParams);
  } catch (error) {
    return error instanceof MiniAppError && error.code === 'INVALID_ARGUMENT' ? error.code :
      vkClientCode(error as Object);
  }
  return '';
}

export default function vkUserInfoHandlerTest(): void {
  describe('VkUserInfoHandler', () => {
    it('rejectsRequestsAfterDisposeWithoutCallingHost', 0, async () => {
      const context = new RecordingUserInfoContext();
      const handler = new VkUsersHandler(context, new VkAdapter({
        onUserInfoRequest: (request: UserInfoRequest): Promise<UserInfoResult> => context.requestUserInfo(request)
      }));
      handler.dispose();
      expect(await captureErrorCode(handler, '{}')).assertEqual('1');
      expect(context.requests.length).assertEqual(0);
    });

    it('rejectsPendingResultAfterDispose', 0, async () => {
      let finish: (result: UserInfoResult) => void = (_result: UserInfoResult): void => {
      };
      const handler = new VkUsersHandler(new RecordingUserInfoContext(), new VkAdapter({
        onUserInfoRequest: (_request: UserInfoRequest): Promise<UserInfoResult> => {
          return new Promise<UserInfoResult>((resolve) => {
            finish = resolve;
          });
        }
      }));
      const pending = captureErrorCode(handler, '{}');
      handler.dispose();
      finish(createUserInfoResult());
      expect(await pending).assertEqual('1');
    });

    it('mapsOptionalOfficialRequestAndReturnsOfficialProfileFields', 0, async () => {
      const context: RecordingUserInfoContext = new RecordingUserInfoContext();
      const handler: VkUsersHandler = new VkUsersHandler(context, new VkAdapter({
        onUserInfoRequest: (request: UserInfoRequest): Promise<UserInfoResult> => context.requestUserInfo(request)
      }));

      const result = await handler.getUserInfo({ user_id: 2314852, user_ids: '2314852' });

      expect(context.requests.length).assertEqual(1);
      expect(context.requests[0].userId).assertEqual(2314852);
      expect(context.requests[0].userIds).assertEqual('2314852');
      expect(result.first_name).assertEqual('Irina');
      expect(result.last_name).assertEqual('Denezhkina');
      expect(result.bdate_visibility).assertEqual(1);
      expect(result.can_access_closed).assertTrue();
      expect(result.is_closed).assertFalse();
      expect(result.photo_100).assertEqual('https://vk.ru/photo-100.jpg');
      expect(result.photo_200).assertEqual('https://vk.ru/photo-200.jpg');
      expect(result.photo_max_orig).assertEqual('https://vk.ru/photo-max.jpg');
    });

    it('supportsEmptyParamsForCurrentUser', 0, async () => {
      const context: RecordingUserInfoContext = new RecordingUserInfoContext();
      const handler: VkUsersHandler = new VkUsersHandler(context, new VkAdapter({
        onUserInfoRequest: (request: UserInfoRequest): Promise<UserInfoResult> => context.requestUserInfo(request)
      }));

      const result = await handler.getUserInfo({});

      expect(context.requests.length).assertEqual(1);
      expect(context.requests[0].userId).assertUndefined();
      expect(context.requests[0].userIds).assertUndefined();
      expect(result.id).assertEqual(2314852);
    });

    it('allowsEmptyUserIdsDeclaredByOfficialBridgeType', 0, async () => {
      const context: RecordingUserInfoContext = new RecordingUserInfoContext();
      const handler: VkUsersHandler = new VkUsersHandler(context, new VkAdapter({
        onUserInfoRequest: (request: UserInfoRequest): Promise<UserInfoResult> => context.requestUserInfo(request)
      }));

      const result = await handler.getUserInfo({ user_ids: '' });

      expect(context.requests.length).assertEqual(1);
      expect(context.requests[0].userIds).assertEqual('');
      expect(result.id).assertEqual(2314852);
    });

    it('rejectsInvalidOptionalParametersBeforeCallingHost', 0, async () => {
      const context: RecordingUserInfoContext = new RecordingUserInfoContext();
      const handler: VkUsersHandler = new VkUsersHandler(context, new VkAdapter({
        onUserInfoRequest: (request: UserInfoRequest): Promise<UserInfoResult> => context.requestUserInfo(request)
      }));

      const invalidUserId = await captureErrorCode(handler, '{"user_id":1.5}');
      const invalidUserIds = await captureErrorCode(handler, '{"user_ids":1}');
      const nullUserId = await captureErrorCode(handler, '{"user_id":null}');

      expect(invalidUserId).assertEqual('5');
      expect(invalidUserIds).assertEqual('INVALID_ARGUMENT');
      expect(nullUserId).assertEqual('INVALID_ARGUMENT');
      expect(context.requests.length).assertEqual(0);
    });
  });
}
