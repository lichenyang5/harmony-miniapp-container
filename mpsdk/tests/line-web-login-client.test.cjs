const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');

function response(method, fields) {
  return Uint8Array.from([0x82, 0x41, 1, method.length, ...Buffer.from(method), ...fields]);
}
test('LIFF WebLogin uses its own exception envelope and refreshes at most once', async () => {
  const load = createLoader();
  const { LineWebLoginClient } = load('main/ets/vendors/line/weblogin/LineWebLoginClient');
  const requests = []; let refreshes = 0;
  const account = {
    getVersion: () => 1, requireAccessToken: () => 'token-a',
    sendAccountRpc: async request => { requests.push(request); return response(request.method,
      [0x3c, 0x15, 0xee, 1, 0, 0]); },
    refreshRejectedToken: async () => { refreshes++; }
  };
  const client = new LineWebLoginClient('liff', account, 'app-a');
  await assert.rejects(client.request({ hookedFullUrl: 'https://access.line.me/dialog/oauth/weblogin' }, true),
    error => error.code === 'LINE_ACCOUNT_ERROR_119');
  assert.equal(requests.length, 2);
  assert.equal(refreshes, 1);
  assert.equal(requests[0].path, '/LIFF1');
  assert.equal(requests[0].liffId, 'app-a');
});

test('browser WebLogin sends ChannelService and does not refresh a Channel code 119', async () => {
  const { LineWebLoginClient } = createLoader()('main/ets/vendors/line/weblogin/LineWebLoginClient');
  const requests = []; let refreshes = 0;
  const account = { getVersion: () => 1, requireAccessToken: () => 'token-a',
    sendAccountRpc: async request => { requests.push(request); return response(request.method, [0x1c, 0x15, 0xee, 1, 0, 0]); },
    refreshRejectedToken: async () => { refreshes++; } };
  await assert.rejects(new LineWebLoginClient('browser', account).request({ hookedFullUrl: 'url' }, false),
    error => error.code === 'LINE_CHANNEL_ERROR_119');
  assert.equal(requests.length, 1);
  assert.equal(requests[0].path, '/CH4');
  assert.equal(requests[0].liffId, undefined);
  assert.equal(refreshes, 0);
});

test('each physical WebLogin response is logged once, including retry and Channel errors', async () => {
  const { reply } = require('./fixtures/line-web-login-rpc.cjs');
  for (const scenario of ['liff-success', 'liff-retry', 'browser-error']) {
    const load = createLoader(undefined, undefined, undefined, undefined, undefined, { DEBUG: true });
    const { LineWebLoginClient } = load('main/ets/vendors/line/weblogin/LineWebLoginClient');
    const { SdkLogger } = load('main/ets/logging/SdkLogger');
    const events = []; SdkLogger.install({ write: (_level, event) => events.push(event) });
    const source = scenario.startsWith('liff') ? 'liff' : 'browser'; let refreshes = 0;
    const account = { getVersion: () => 1, requireAccessToken: () => 'token',
      sendAccountRpc: async request => scenario === 'liff-success' ?
        reply(source, request.method, 1, { returnUrl: 'https://shop.example/callback' }) :
        response(request.method, [source === 'browser' ? 0x1c : 0x3c, 0x15, 0xee, 1, 0, 0]),
      refreshRejectedToken: async () => { refreshes++; } };
    const result = new LineWebLoginClient(source, account, 'app').request({ hookedFullUrl: 'url' }, true);
    if (scenario === 'liff-success') assert.equal((await result).returnUrl, 'https://shop.example/callback');
    else await assert.rejects(result, { code: source === 'browser' ? 'LINE_CHANNEL_ERROR_119' : 'LINE_ACCOUNT_ERROR_119' });
    assert.equal(events.filter(event => event.endsWith('Response')).length, scenario === 'liff-retry' ? 2 : 1);
    assert.equal(refreshes, scenario === 'liff-retry' ? 1 : 0);
  }
});
