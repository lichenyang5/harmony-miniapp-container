const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { createTestSession } = require('./test-session.cjs');

test('required assertions distinguish missing values from invalid values', () => {
  const load = createLoader();
  const { ParamAssert } = load('main/ets/utils/ParamAssert');
  const { VkBridgeProtocol } = load('main/ets/vendors/vk/VkBridgeProtocol');
  const validators = [
    value => ParamAssert.assertString(value, 'field', false),
    value => ParamAssert.assertNumber(value, 'field'),
    value => ParamAssert.assertBoolean(value, 'field'),
    value => ParamAssert.assertStringArray(value, 'field'),
    value => ParamAssert.assertObject(value, 'field'),
    value => ParamAssert.assertEnum(value, 'field', ['light', 'dark'])
  ];
  for (const validate of validators) {
    for (const [value, sdkCode, code, reason] of [
      [undefined, 'MISSING_REQUIRED_PARAMS', 2, 'Missing required params'],
      [null, 'INVALID_ARGUMENT', 5, 'Invalid params']
    ]) {
      assert.throws(() => validate(value), error => {
        assert.equal(error.code, sdkCode);
        assert.deepEqual(VkBridgeProtocol.failure('Failed', 42, error), {
          type: 'Failed', data: { request_id: 42, error_type: 'client_error',
            error_data: { error_code: code, error_reason: reason } }
        });
        return true;
      });
    }
  }
  for (const value of ['', 1, false]) {
    assert.throws(() => ParamAssert.assertString(value, 'field', false), { code: 'INVALID_ARGUMENT' });
  }
  for (const value of ['1', NaN, Infinity]) {
    assert.throws(() => ParamAssert.assertNumber(value, 'field'), { code: 'INVALID_ARGUMENT' });
  }
  assert.throws(() => ParamAssert.assertEnum('other', 'field', ['light']), { code: 'INVALID_ARGUMENT' });
  assert.throws(() => ParamAssert.assertStringArray([undefined], 'field'), { code: 'INVALID_ARGUMENT' });
});

test('optional values may be omitted while explicit null remains invalid', () => {
  const { ParamAssert } = createLoader()('main/ets/utils/ParamAssert');
  for (const validate of [ParamAssert.assertOptionalString, ParamAssert.assertOptionalNumber,
    ParamAssert.assertOptionalBoolean]) {
    validate(undefined, 'optional');
    assert.throws(() => validate(null, 'optional'), { code: 'INVALID_ARGUMENT' });
  }
  ParamAssert.assertNumber(0, 'zero');
  ParamAssert.assertBoolean(false, 'false');
  ParamAssert.assertString('', 'empty');
  ParamAssert.assertStringArray([], 'emptyArray');
});

test('registered requests return missing 2 and invalid 5 with their original route', async () => {
  const load = createLoader();
  const sent = [];
  const context = createTestSession(load, { id: 'params', appId: 'params',
    onScript(script) {
      new Function('window', script)({ atomicBridge: { postResponse(route, event) { sent.push({ route, event }); } } });
    }
  });
  const binding = context.getBinding();
  try {
    for (const [method, field, invalid] of [
      ['VKWebAppFlashSetLevel', 'level', 2],
      ['VKWebAppTapticImpactOccurred', 'style', 'other'],
      ['VKWebAppTapticNotificationOccurred', 'type', 'other'],
      ['VKWebAppSetViewSettings', 'status_bar_style', 'other'],
      ['VKWebAppSetSwipeSettings', 'history', 1]
    ]) {
      for (const [value, code] of [[undefined, 2], [null, 5], [invalid, 5]]) {
        const params = { request_id: 7, [field]: value };
        binding.injections[0].object.onInterceptRequest(JSON.stringify({ type: 'vk-connect', handler: method, params }), 'route');
        for (let index = 0; index < 20; index++) await Promise.resolve();
        assert.equal(sent.length, 1);
        const response = sent.pop();
        assert.equal(response.route, 'route');
        assert.equal(response.event.type, method + 'Failed');
        assert.equal(response.event.data.request_id, 7);
        assert.equal(response.event.data.error_data.error_code, code);
      }
    }
  } finally { context.close(); }
});
