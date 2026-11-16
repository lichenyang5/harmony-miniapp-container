import { describe, expect, it } from '@ohos/hypium';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import {
  INVALID_ARGUMENT,
  MISSING_REQUIRED_PARAMS,
  NOT_SUPPORTED,
  PERMISSION_DENIED,
  SYSTEM_ERROR,
  USER_CANCELLED
} from '../main/ets/core/MiniAppErrorCode';
import { ParamAssert } from '../main/ets/utils/ParamAssert';
import { VkApiErrorData, VkAuthErrorData, VkBridgeError } from '../main/ets/vendors/vk/VkBridgeError';
import { VkClientErrorCode } from '../main/ets/vendors/vk/VkClientErrorCode';
import { VkBridgeProtocol } from '../main/ets/vendors/vk/VkBridgeProtocol';

export default function vkBridgeErrorTest(): void {
  describe('VkBridgeError', () => {
    it('convertsSdkParameterErrors', 0, () => {
      const codes: string[] =
        [USER_CANCELLED, INVALID_ARGUMENT, MISSING_REQUIRED_PARAMS, NOT_SUPPORTED, PERMISSION_DENIED, SYSTEM_ERROR];
      const values: number[] = [1, 5, 2, 1, 1, 1];
      codes.forEach((code: string, index: number): void => {
        const data =
          JSON.stringify(VkBridgeProtocol.failure('Failed', undefined, new MiniAppError(code, 'private-secret')).data);
        expect(data).assertContain('"error_code":' + values[index]);
        expect(data.includes('private-secret')).assertFalse();
      });
    });
    it('convertsMissingRequiredValuesAtProtocolBoundary', 0, () => {
      try {
        ParamAssert.assertNumber(undefined, 'level');
        expect(false).assertTrue();
      } catch (error) {
        expect((error as MiniAppError).code).assertEqual(MISSING_REQUIRED_PARAMS);
        expect(JSON.stringify(VkBridgeProtocol.failure('Failed', undefined, error as Object).data))
          .assertContain('"error_code":2');
      }
      ParamAssert.assertOptionalNumber(undefined, 'level');
    });
    it('preservesExplicitApiAndAuthShapes', 0, () => {
      const apiData: VkApiErrorData = { error_code: 5, error_msg: 'API failure', request_params: ['safe'] };
      const api = VkBridgeError.api(apiData);
      expect(api instanceof MiniAppError).assertTrue();
      expect(JSON.stringify(VkBridgeProtocol.failure('Failed', undefined, api).data))
        .assertEqual(JSON.stringify(api.toData()));
      expect(JSON.stringify(api.toData())).assertEqual(
        '{"error_type":"api_error","error_data":{"error_code":5,"error_msg":"API failure","request_params":["safe"]}}');
      const authData: VkAuthErrorData = { error: 7, error_reason: 'Auth failure', error_description: ['detail'] };
      expect(JSON.stringify(VkBridgeError.auth(authData).toData())).assertEqual(
        '{"error_type":"auth_error","error_data":{"error":7,"error_reason":"Auth failure","error_description":["detail"]}}');
      expect(JSON.stringify(VkBridgeError.client(VkClientErrorCode.USER_DENIED).toData())).assertContain('User denied');
    });
  });
}
