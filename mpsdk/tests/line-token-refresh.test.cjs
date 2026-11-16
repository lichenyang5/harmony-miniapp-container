const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function compactString(value) { return [Buffer.byteLength(value), ...Buffer.from(value)]; }
function reply(method, sequence, fields) {
  return Uint8Array.from([0x82, 0x41, sequence, ...compactString(method), ...fields]);
}

test('V3 refresh uses the APK refresh RPC envelope and reads rotated tokens', () => {
  const load = createLoader();
  const { LineTokenRefreshCodec } = load('main/ets/vendors/line/auth/LineTokenRefreshCodec');
  const str = value => [Buffer.byteLength(value), ...Buffer.from(value)];
  assert.deepEqual(Array.from(LineTokenRefreshCodec.encodeRefreshToken('old-refresh', 7)),
    [0x82, 0x21, 7, ...str('refresh'), 0x1c, 0x18, ...str('old-refresh'), 0, 0]);
  const reply = Uint8Array.from([0x82, 0x41, 7, ...str('refresh'), 0x0c, 0,
    0x18, ...str('new-access'), 0x16, 0xb0, 0x09,
    0x1c, 0, 0x28, ...str('new-refresh'), 0, 0]);
  assert.deepEqual(LineTokenRefreshCodec.decodeRefreshToken(reply, 7), {
    accessToken: 'new-access', refreshToken: 'new-refresh', durationUntilRefreshInSec: 600
  });
});

test('refresh errors preserve the APK numeric reason separately from QR errors', () => {
  const load = createLoader();
  const { LineTokenRefreshCodec } = load('main/ets/vendors/line/auth/LineTokenRefreshCodec');
  const failure = reply('refresh', 1, [0x1c, 0x15, 0xd0, 0x0f, 0x16, 14, 0, 0]);
  assert.throws(() => LineTokenRefreshCodec.decodeRefreshToken(failure, 1), error =>
    error.code === 'LINE_TOKEN_REFRESH_ERROR_1000_REASON_7');
});

test('report uses nested accessToken and requires the APK empty success struct', () => {
  const { LineTokenRefreshCodec: codec } = createLoader()('main/ets/vendors/line/auth/LineTokenRefreshCodec');
  const method = 'reportRefreshedAccessToken';
  assert.deepEqual(Array.from(codec.encodeReportRefreshedAccessToken('current-access', 9)),
    [0x82, 0x21, 9, ...compactString(method), 0x1c, 0x18, ...compactString('current-access'), 0, 0]);
  assert.doesNotThrow(() => codec.decodeReportRefreshedAccessToken(reply(method, 9, [0x0c, 0, 0, 0]), 9));
  // Unknown fields remain forward compatible; an absent success is not a successful report.
  assert.doesNotThrow(() => codec.decodeReportRefreshedAccessToken(
    reply(method, 9, [0x0c, 0, 0x18, ...compactString('future'), 0, 0]), 9));
  for (const bytes of [reply(method, 9, [0]), reply(method, 8, [0x0c, 0, 0, 0]),
    reply('refresh', 9, [0x0c, 0, 0, 0]), reply(method, 9, [0x0c, 0, 0, 0, 0]),
    reply(method, 9, [0x0c, 0, 0, 0x18, ...compactString('bad-error'), 0]),
    reply(method, 9, [0x1c, 0x18, ...compactString('bad-code'), 0, 0])]) {
    assert.throws(() => codec.decodeReportRefreshedAccessToken(bytes, 9));
  }
  assert.throws(() => codec.decodeReportRefreshedAccessToken(
    reply(method, 9, [0x1c, 0x15, 0xd0, 0x0f, 0x16, 4, 0, 0]), 9),
  error => error.code === 'LINE_TOKEN_REFRESH_ERROR_1000_REASON_2');
});
