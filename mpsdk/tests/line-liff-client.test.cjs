const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('LIFF refresh never retries an old request against a replacement account', async () => {
  const { LineLiffClient } = createLoader()('main/ets/vendors/line/liff/LineLiffClient');
  let version = 0;
  let sends = 0;
  const method = 'issueLiffView';
  const rejection = Uint8Array.from([0x82, 0x41, 3, method.length, ...Buffer.from(method),
    0x2c, 0x15, 0xee, 1, 0, 0]);
  const client = new LineLiffClient({
    getVersion: () => version,
    requireAccessToken: () => 'account-A-token',
    sendAccountRpc: async () => { sends++; return rejection; },
    refreshRejectedToken: async (token, generation) => {
      assert.equal(token, 'account-A-token');
      assert.equal(generation, 0);
      version++; // Account switches while the awaited refresh continuation completes.
    }
  });
  await assert.rejects(client.send(method, new Uint8Array([1]), 'app', 3),
    error => error.code === 'LINE_LOGIN_CANCELLED');
  assert.equal(sends, 1);
});
