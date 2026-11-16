import { VkBridgeError } from '../main/ets/vendors/vk/VkBridgeError';
import { VkClientErrorCode } from '../main/ets/vendors/vk/VkClientErrorCode';
import { describe, expect, it } from '@ohos/hypium';
import { InterceptResult } from '../main/ets/vendors/vk/VkBridgeProxy';
import { VkBridgeProtocol } from '../main/ets/vendors/vk/VkBridgeProtocol';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { INVALID_ARGUMENT } from '../main/ets/core/MiniAppErrorCode';

export default function vkBridgeProtocolTest(): void {
  describe('VkBridgeProtocol', () => {
    it('parsesOfficialWebRequestEnvelope', 0, () => {
      const request = VkBridgeProtocol.parseRequest(
        '{"type":"vk-connect","handler":"VKWebAppTapticImpactOccurred",' +
          '"params":{"style":"medium","request_id":"2_x"}}')?.request;

      expect(request !== undefined).assertTrue();
      expect(request?.method).assertEqual('VKWebAppTapticImpactOccurred');
      expect(request?.requestId).assertEqual('2_x');
      expect(JSON.stringify(request?.params)).assertContain('"style":"medium"');
    });

    it('retainsRequestMethodWhenParamsAreMalformed', 0, () => {
      const parsed = VkBridgeProtocol.parseRequest(
        '{"type":"vk-connect","handler":"VKWebAppClose","params":null}');

      expect(parsed?.method).assertEqual('VKWebAppClose');
      expect(parsed?.request).assertUndefined();
    });

    it('passesMessagesOutsideVkWebProtocol', 0, () => {
      expect(VkBridgeProtocol.parseRequest('{"type":"other","handler":"VKWebAppInit"}') === undefined)
        .assertTrue();
      expect(VkBridgeProtocol.parseRequest('invalid-json') === undefined).assertTrue();
    });

    it('buildsOfficialSuccessEnvelope', 0, () => {
      const event = VkBridgeProtocol.success(
        'VKWebAppTapticSelectionChangedResult', 3, JSON.parse('{"result":true}') as Object);
      const data = event.data as Record<string, Object>;

      expect(event.type).assertEqual('VKWebAppTapticSelectionChangedResult');
      expect(data['result']).assertTrue();
      expect(data['request_id']).assertEqual(3);
    });

    it('buildsOfficialClientErrorEnvelope', 0, () => {
      const event = VkBridgeProtocol.failure('VKWebAppTapticImpactOccurredFailed', '2_x',
        VkBridgeError.client(VkClientErrorCode.INVALID_PARAMS));
      const data = event.data as Record<string, Object>;
      const errorData = data['error_data'] as Record<string, Object>;

      expect(event.type).assertEqual('VKWebAppTapticImpactOccurredFailed');
      expect(data['error_type']).assertEqual('client_error');
      expect(data['request_id']).assertEqual('2_x');
      expect(errorData['error_code']).assertEqual(5);
      expect(errorData['error_reason']).assertEqual('Invalid params');
    });

    it('buildsOfficialAuthTokenSuccessEventName', 0, () => {
      const event = VkBridgeProtocol.success(
        'VKWebAppAccessTokenReceived', 'auth_1',
        JSON.parse('{"access_token":"token","scope":"friends"}') as Object);

      expect(event.type).assertEqual('VKWebAppAccessTokenReceived');
      expect((event.data as Record<string, Object>)['request_id']).assertEqual('auth_1');
    });

    it('buildsOfficialAuthTokenFailureEventName', 0, () => {
      const event = VkBridgeProtocol.failure('VKWebAppAccessTokenFailed', 'auth_2', new Error('private'));

      expect(event.type).assertEqual('VKWebAppAccessTokenFailed');
      expect((event.data as Record<string, Object>)['request_id']).assertEqual('auth_2');
    });

    it('mergesSupportedHandlersWithoutDuplicates', 0, () => {
      const handlers = VkBridgeProtocol.mergeSupportedHandlers(
        ['VKWebAppInit'], ['VKWebAppInit', 'VKWebAppTapticSelectionChanged']);

      expect(handlers.length).assertEqual(2);
      expect(handlers[0]).assertEqual('VKWebAppInit');
      expect(handlers[1]).assertEqual('VKWebAppTapticSelectionChanged');
    });

    it('passesUnownedMessages', 0, () => {
      const result: InterceptResult = InterceptResult.pass();
      expect(result.intercept).assertFalse();
      expect(result.data === undefined).assertTrue();
      expect(result.timeout === undefined).assertTrue();
    });

    it('suppressesOwnedMessages', 0, () => {
      const result: InterceptResult = InterceptResult.intercept();
      expect(result.intercept).assertTrue();
      expect(result.data === undefined).assertTrue();
      expect(result.timeout === undefined).assertTrue();
    });

    it('forwardsHookedMessages', 0, () => {
      const payload: object = JSON.parse('{"type":"SetSupportedHandlers"}') as object;
      const result: InterceptResult = InterceptResult.hook(payload);
      expect(result.intercept).assertFalse();
      expect(result.data === payload).assertTrue();
      expect(result.timeout === undefined).assertTrue();
    });
  });
}
