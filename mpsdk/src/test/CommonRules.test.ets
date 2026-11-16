import { describe, expect, it } from '@ohos/hypium';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { INVALID_ARGUMENT, SYSTEM_ERROR } from '../main/ets/core/MiniAppErrorCode';
import { JsonObjectReader } from '../main/ets/vendors/vk/JsonObjectReader';

export default function commonRulesTest(): void {
  describe('CommonRules', () => {
    it('readsSupportedFields', 0, () => {
      const reader = JsonObjectReader.from(
        '{"name":"vk","count":2,"enabled":true,"request_id":"7_a"}');
      expect(reader.requiredString('name')).assertEqual('vk');
      expect(reader.requiredNumber('count')).assertEqual(2);
      expect(reader.optionalBoolean('enabled')).assertTrue();
      expect(reader.optionalRequestId('request_id')).assertEqual('7_a');
    });

    it('rejectsNonObjectJson', 0, () => {
      let code = '';
      try {
        JsonObjectReader.from('[]');
      } catch (error) {
        code = (error as MiniAppError).code;
      }
      expect(code).assertEqual(INVALID_ARGUMENT);
    });

    it('rejectsWrongFieldType', 0, () => {
      let code = '';
      try {
        JsonObjectReader.from('{"name":1}').requiredString('name');
      } catch (error) {
        code = (error as MiniAppError).code;
      }
      expect(code).assertEqual(INVALID_ARGUMENT);
    });

    it('preservesSdkErrorsAtNativeBoundary', 0, () => {
      const source: MiniAppError = new MiniAppError('TEST_ERROR', '测试错误');
      const result: MiniAppError = MiniAppError.from(source, SYSTEM_ERROR, '系统错误');
      expect(result.code).assertEqual('TEST_ERROR');
      expect(result.message).assertEqual('测试错误');
    });

    it('wrapsPlatformErrorsAtNativeBoundary', 0, () => {
      const source: Error = new Error('camera failed');
      const result: MiniAppError = MiniAppError.from(source, SYSTEM_ERROR, '设置闪光灯失败');
      expect(result.code).assertEqual(SYSTEM_ERROR);
      expect(result.message).assertEqual('设置闪光灯失败');
    });
  });
}
