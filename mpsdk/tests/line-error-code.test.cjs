const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { LineErrorCode, LineBridgeErrorCode } = createLoader()('main/ets/vendors/line/LineErrorCode');

test('service errors retain unknown numeric codes and an explicit zero refresh reason', () => {
  assert.equal(LineErrorCode.qrService(-1), 'LINE_QR_SERVICE_ERROR');
  assert.equal(LineErrorCode.qrService(9876), 'LINE_QR_SERVICE_ERROR_9876');
  assert.equal(LineErrorCode.tokenRefresh(1000), 'LINE_TOKEN_REFRESH_ERROR_1000');
  assert.equal(LineErrorCode.tokenRefresh(1000, 0), 'LINE_TOKEN_REFRESH_ERROR_1000_REASON_0');
  assert.equal(LineErrorCode.accountService(119), LineErrorCode.ACCOUNT_MUST_REFRESH);
  assert.equal(LineErrorCode.liffService(119), 'LINE_LIFF_ERROR_119');
});

test('native diagnostic selection does not confuse QR, refresh and Bridge error contracts', () => {
  assert.equal(LineErrorCode.isQrService('LINE_QR_SERVICE_ERROR_100'), true);
  for (const code of ['LINE_QR_SERVICE_ERROR', 'LINE_QR_SERVICE_ERROR_100x',
    'LINE_TOKEN_REFRESH_ERROR_1000', LineBridgeErrorCode.NO_AUTHORITY]) {
    assert.equal(LineErrorCode.isQrService(code), false);
  }
  assert.equal(LineBridgeErrorCode.NO_AUTHORITY, 'NO_AUTHORITY');
  assert.equal(LineErrorCode.nativeDiagnostic(24000002), 'NATIVE_24000002');
});

test('only refresh INVALID_REQUEST asks for a new login, preserving unknown and transient errors', () => {
  for (const code of ['LINE_TOKEN_REFRESH_ERROR_1000', 'LINE_TOKEN_REFRESH_ERROR_1000_REASON_0',
    'LINE_TOKEN_REFRESH_ERROR_1000_REASON_2']) {
    assert.equal(LineErrorCode.isTokenRefreshRejected(code), true);
  }
  for (const code of ['LINE_RPC_NETWORK_FAILED', 'LINE_RPC_TIMEOUT', 'LINE_RPC_HTTP_FAILED',
    'LINE_TOKEN_REFRESH_ERROR_1001', 'LINE_TOKEN_REFRESH_ERROR_10000_REASON_2',
    'LINE_QR_SERVICE_ERROR_1000', 'LINE_QR_PROTOCOL_ERROR']) {
    assert.equal(LineErrorCode.isTokenRefreshRejected(code), false);
  }
});
