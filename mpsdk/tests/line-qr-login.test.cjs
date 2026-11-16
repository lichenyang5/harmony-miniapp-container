const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('empty certificate is encoded without calling Harmony TextEncoder for an empty string', () => {
  const load = createLoader({}, {}, undefined, {}, () => true, { DEBUG: false }, {
    '@kit.ArkTS': { util: {
      TextEncoder: class {
        encodeInto(value) {
          if (value === '') throw new TypeError('Harmony empty input');
          return new TextEncoder().encode(value);
        }
      }
    } }
  });
  const { LineQrLoginCodec } = load('main/ets/vendors/line/auth/LineQrLoginCodec');
  const bytes = LineQrLoginCodec.encodeVerifyCertificate('session-1', '', 1);
  assert.equal(bytes.at(-3), 0);
});

function compactString(value) {
  const bytes = Array.from(Buffer.from(value, 'utf8'));
  return [bytes.length, ...bytes];
}

function reply(method, sequence, fields) {
  return new Uint8Array([0x82, 0x41, sequence, ...compactString(method), ...fields]);
}

test('service alert is retained only as the native original cause', () => {
  const load = createLoader();
  const { LineQrLoginCodec } = load('main/ets/vendors/line/auth/LineQrLoginCodec');
  const failure = reply('qrCodeLoginV2ForSecure', 7,
    [0x1c, 0x15, 0xc8, 1, 0x18, ...compactString('private service alert'), 0, 0]);
  assert.throws(() => LineQrLoginCodec.decodeQrCodeLogin(failure, 7), error => {
    assert.equal(error.code, 'LINE_QR_SERVICE_ERROR_100');
    assert.equal(error.originalCause.message, 'private service alert');
    assert.equal(error.message.includes('private service alert'), false);
    return true;
  });
});

test('QR login session request and response use the APK Compact contract', () => {
  const load = createLoader();
  const { LineQrLoginCodec } = load('main/ets/vendors/line/auth/LineQrLoginCodec');
  assert.deepEqual(Array.from(LineQrLoginCodec.encodeCreateSession(7)),
    [0x82, 0x21, 7, ...compactString('createSession'), 0x1c, 0, 0]);
  const response = reply('createSession', 7, [0x0c, 0, 0x18, ...compactString('session-1'), 0, 0]);
  assert.equal(LineQrLoginCodec.decodeCreateSession(response, 7), 'session-1');
});

test('secure QR request and response preserve nonce and polling limits', () => {
  const load = createLoader();
  const { LineQrLoginCodec } = load('main/ets/vendors/line/auth/LineQrLoginCodec');
  assert.deepEqual(Array.from(LineQrLoginCodec.encodeCreateQrCode('session-1', 8)),
    [0x82, 0x21, 8, ...compactString('createQrCodeForSecure'), 0x1c,
      0x18, ...compactString('session-1'), 0, 0]);
  const response = reply('createQrCodeForSecure', 8,
    [0x0c, 0, 0x18, ...compactString('https://line.example/qr'),
      0x15, 10, 0x15, 4, 0x18, ...compactString('server-nonce'), 0, 0]);
  assert.deepEqual(LineQrLoginCodec.decodeCreateQrCode(response, 8), {
    callbackUrl: 'https://line.example/qr', longPollingMaxCount: 5,
    longPollingIntervalSec: 2, nonce: 'server-nonce'
  });
});

test('zero long poll interval remains valid for the APK default wait', () => {
  const load = createLoader();
  const { LineQrLoginCodec } = load('main/ets/vendors/line/auth/LineQrLoginCodec');
  const response = reply('createQrCodeForSecure', 1,
    [0x0c, 0, 0x18, ...compactString('https://line.example/qr'),
      0x15, 2, 0x15, 0, 0x18, ...compactString('nonce'), 0, 0]);
  assert.equal(LineQrLoginCodec.decodeCreateQrCode(response, 1).longPollingIntervalSec, 0);
});

test('QR login rejects mismatched, truncated, missing and failed replies', () => {
  const load = createLoader();
  const { LineQrLoginCodec } = load('main/ets/vendors/line/auth/LineQrLoginCodec');
  const valid = reply('createSession', 1, [0x0c, 0, 0x18, ...compactString('s'), 0, 0]);
  for (const bytes of [valid.slice(0, -1), reply('other', 1, [0]),
    reply('createSession', 2, [0]), reply('createSession', 1, [0])]) {
    assert.throws(() => LineQrLoginCodec.decodeCreateSession(bytes, 1));
  }
  const failure = reply('createSession', 1, [0x1c, 0x15, 4, 0x18,
    ...compactString('private service text'), 0, 0]);
  assert.throws(() => LineQrLoginCodec.decodeCreateSession(failure, 1),
    error => error.code === 'LINE_QR_SERVICE_ERROR_2' &&
      !error.message.includes('private service text'));
});

test('QR verification long poll uses session ID and accepts an empty success struct', () => {
  const load = createLoader();
  const { LineQrLoginCodec } = load('main/ets/vendors/line/auth/LineQrLoginCodec');
  assert.deepEqual(Array.from(LineQrLoginCodec.encodeCheckQrCodeVerified('session-1', 9)),
    [0x82, 0x21, 9, ...compactString('checkQrCodeVerified'), 0x1c,
      0x18, ...compactString('session-1'), 0, 0]);
  const response = reply('checkQrCodeVerified', 9, [0x0c, 0, 0, 0]);
  assert.equal(LineQrLoginCodec.decodeCheckQrCodeVerified(response, 9), true);
  assert.throws(() => LineQrLoginCodec.decodeCheckQrCodeVerified(
    reply('checkQrCodeVerified', 9, [0]), 9));
});

test('PIN request and response use the login session rather than account token', () => {
  const load = createLoader();
  const { LineQrLoginCodec } = load('main/ets/vendors/line/auth/LineQrLoginCodec');
  assert.deepEqual(Array.from(LineQrLoginCodec.encodeCreatePinCode('session-1', 10)),
    [0x82, 0x21, 10, ...compactString('createPinCode'), 0x1c,
      0x18, ...compactString('session-1'), 0, 0]);
  assert.equal(LineQrLoginCodec.decodeCreatePinCode(
    reply('createPinCode', 10, [0x0c, 0, 0x18, ...compactString('123456'), 0, 0]), 10), '123456');
});

test('PIN confirmation long poll requires the service success struct', () => {
  const load = createLoader();
  const { LineQrLoginCodec } = load('main/ets/vendors/line/auth/LineQrLoginCodec');
  assert.deepEqual(Array.from(LineQrLoginCodec.encodeCheckPinCodeVerified('session-1', 12)),
    [0x82, 0x21, 12, ...compactString('checkPinCodeVerified'), 0x1c,
      0x18, ...compactString('session-1'), 0, 0]);
  assert.equal(LineQrLoginCodec.decodeCheckPinCodeVerified(
    reply('checkPinCodeVerified', 12, [0x0c, 0, 0, 0]), 12), true);
  assert.throws(() => LineQrLoginCodec.decodeCheckPinCodeVerified(
    reply('checkPinCodeVerified', 12, [0]), 12));
});

test('certificate verification sends an empty certificate on first login and falls back to PIN only for code 2', () => {
  const load = createLoader();
  const { LineQrLoginCodec } = load('main/ets/vendors/line/auth/LineQrLoginCodec');
  assert.deepEqual(Array.from(LineQrLoginCodec.encodeVerifyCertificate('session-1', '', 13)),
    [0x82, 0x21, 13, ...compactString('verifyCertificate'), 0x1c,
      0x18, ...compactString('session-1'), 0x18, ...compactString(''), 0, 0]);
  assert.equal(LineQrLoginCodec.decodeVerifyCertificate(
    reply('verifyCertificate', 13, [0x0c, 0, 0, 0]), 13), true);
  assert.equal(LineQrLoginCodec.decodeVerifyCertificate(
    reply('verifyCertificate', 13, [0x1c, 0x15, 4, 0, 0]), 13), false);
  assert.throws(() => LineQrLoginCodec.decodeVerifyCertificate(
    reply('verifyCertificate', 13, [0x1c, 0x15, 2, 0, 0]), 13));
});

test('final QR login uses explicit auto-login bool and reads V3 credential, never V2 token', () => {
  const load = createLoader();
  const { LineQrLoginCodec } = load('main/ets/vendors/line/auth/LineQrLoginCodec');
  const request = {
    authSessionId: 'session-1', systemName: 'device', modelName: 'model', nonce: 'server-nonce',
    autoLoginIsRequired: true
  };
  assert.deepEqual(Array.from(LineQrLoginCodec.encodeQrCodeLogin(request, 11)),
    [0x82, 0x21, 11, ...compactString('qrCodeLoginV2ForSecure'), 0x1c,
      0x18, ...compactString('session-1'), 0x18, ...compactString('device'),
      0x18, ...compactString('model'), 0x11, 0x18, ...compactString('server-nonce'), 0, 0]);
  const response = reply('qrCodeLoginV2ForSecure', 11, [0x0c, 0,
    0x18, ...compactString('certificate'),
    0x18, ...compactString('obsolete-v2'),
    0x1c, // field 3: TokenV3IssueResult
      0x18, ...compactString('v3-access'),
      0x18, ...compactString('v3-refresh'),
      0x16, 0xd0, 0x0f, // duration 1000 seconds, zigzag 2000
      0x1c, 0, // retry policy struct
      0x18, ...compactString('login-session'),
      0, // V3 struct
    0x18, ...compactString('user-mid'),
    0x6b, 0, // field 10: empty metadata map
    0, 0]);
  const result = LineQrLoginCodec.decodeQrCodeLogin(response, 11);
  assert.equal(result.accessToken, 'v3-access');
  assert.equal(result.refreshToken, 'v3-refresh');
  assert.equal(result.mid, 'user-mid');
  assert.equal(result.loginSessionId, 'login-session');
  assert.equal(result.certificate, 'certificate');
  assert.equal(result.durationUntilRefreshInSec, 1000);
  assert.equal(result.metaData.size, 0);
});
