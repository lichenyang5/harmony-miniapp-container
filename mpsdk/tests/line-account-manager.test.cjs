const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function credential(mid) {
  return { mid, accessToken: 'secret-' + mid, refreshToken: 'refresh', certificate: 'cert',
    loginSessionId: 'session', durationUntilRefreshInSec: 300, metaData: new Map() };
}

function thriftString(value) { return [Buffer.byteLength(value), ...Buffer.from(value)]; }

test('official consent headers reuse the current native token and exact transport application profile', async () => {
  const { LineAccountManager } = createLoader()('main/ets/vendors/line/auth/LineAccountManager');
  const transport = { applicationHeader: 'CUSTOM_SECONDARY\t1\tOS\t2', send: async () => new Uint8Array() };
  const manager = new LineAccountManager({ cancel() {}, login: async () => credential('native') },
    'device', 'model', transport);
  assert.throws(() => manager.getWebAuthHeaders(), error => error.code === 'LINE_LOGIN_REQUIRED');
  await manager.startQrLogin(() => {});
  assert.deepEqual(manager.getWebAuthHeaders(), {
    'X-Line-Access': 'secret-native', 'X-Line-Application': transport.applicationHeader
  });
  manager.logout();
  assert.throws(() => manager.getWebAuthHeaders(), error => error.code === 'LINE_LOGIN_REQUIRED');
});

test('LIFF TalkException 119 refreshes V3 token and retries once with the new access token', async () => {
  const { LineAccountManager } = createLoader()('main/ets/vendors/line/auth/LineAccountManager');
  const requests = [];
  const transport = { send: async request => {
    requests.push(request);
    if (request.path === '/EXT/auth/tokenrefresh/v1') {
      if (request.method === 'reportRefreshedAccessToken') {
        return Uint8Array.from([0x82, 0x41, request.body[2], ...thriftString(request.method), 0x0c, 0, 0, 0]);
      }
      return Uint8Array.from([0x82, 0x41, request.body[2], ...thriftString('refresh'), 0x0c, 0,
        0x18, ...thriftString('rotated-access'), 0x16, 0xb0, 0x09,
        0x1c, 0, 0x28, ...thriftString('rotated-refresh'), 0, 0]);
    }
    if (requests.filter(item => item.path === '/LIFF1').length === 1) {
      return Uint8Array.from([0x82, 0x41, 3, ...thriftString('issueLiffView'),
        0x2c, 0x15, 0xee, 0x01, 0, 0]);
    }
    return Uint8Array.from([0x82, 0x41, 3, ...thriftString('issueLiffView'), 0x0c, 0, 0, 0]);
  } };
  const manager = new LineAccountManager({ cancel() {}, login: async () => credential('mid-1') },
    'device', 'model', transport);
  await manager.startQrLogin(() => {});
  await manager.sendLiffRpc('issueLiffView', new Uint8Array([1]), 'app-id', 3);
  assert.deepEqual(requests.map(item => item.path),
    ['/LIFF1', '/EXT/auth/tokenrefresh/v1', '/EXT/auth/tokenrefresh/v1', '/EXT/auth/tokenrefresh/v1', '/LIFF1']);
  assert.equal(requests[0].sessionAccess, 'secret-mid-1');
  assert.equal(requests[1].sessionAccess, 'secret-mid-1');
  assert.equal(requests[2].sessionAccess, 'secret-mid-1');
  assert.equal(requests[3].sessionAccess, 'rotated-access');
  assert.equal(requests[4].sessionAccess, 'rotated-access');
  assert.equal(manager.requireAccessToken(), 'rotated-access');
  manager.logout();
});

test('account becomes available only after login completes; logout invalidates it', async () => {
  const { LineAccountManager } = createLoader()('main/ets/vendors/line/auth/LineAccountManager');
  let finish;
  const runner = { cancel() {}, login: async (_system, _model, onState) => {
    onState({ kind: 'qrReady', url: 'https://line.example/qr' });
    return new Promise(resolve => { finish = resolve; });
  } };
  const manager = new LineAccountManager(runner, 'device', 'model');
  const events = [];
  const pending = manager.startQrLogin(event => events.push(event));
  while (!finish) await new Promise(resolve => setImmediate(resolve));
  assert.equal(manager.getAccountId(), undefined);
  assert.throws(() => manager.requireAccessToken(), error => error.code === 'LINE_LOGIN_REQUIRED');
  finish(credential('mid-1'));
  assert.equal(await pending, 'mid-1');
  assert.equal(manager.getAccountId(), 'mid-1');
  assert.equal(events.at(-1).kind, 'authorized');
  manager.logout();
  assert.equal(manager.getAccountId(), undefined);
  assert.throws(() => manager.requireAccessToken(), error => error.code === 'LINE_LOGIN_REQUIRED');
});

test('logout and replacement discard late login results', async () => {
  const { LineAccountManager } = createLoader()('main/ets/vendors/line/auth/LineAccountManager');
  const completions = [];
  let cancelled = 0;
  const runner = { cancel() { cancelled++; }, login: async () => new Promise(resolve => completions.push(resolve)) };
  const manager = new LineAccountManager(runner, 'device', 'model');
  const first = manager.startQrLogin(() => {});
  const second = manager.startQrLogin(() => {});
  completions[0](credential('stale'));
  await assert.rejects(first, error => error.code === 'LINE_LOGIN_CANCELLED');
  assert.equal(manager.getAccountId(), undefined);
  completions[1](credential('current'));
  assert.equal(await second, 'current');
  manager.logout();
  assert.equal(manager.getAccountId(), undefined);
  assert.ok(cancelled >= 2);
});

test('an old login version cannot cancel a newer authentication', async () => {
  const { LineAccountManager } = createLoader()('main/ets/vendors/line/auth/LineAccountManager');
  const completions = [];
  const manager = new LineAccountManager({ cancel() {}, login: () =>
    new Promise(resolve => completions.push(resolve)) }, 'device', 'model');
  let oldVersion;
  const first = manager.startQrLogin(() => {}, version => { oldVersion = version; });
  let newVersion;
  const second = manager.startQrLogin(() => {}, version => { newVersion = version; });
  manager.cancelQrLogin(oldVersion);
  assert.equal(manager.getVersion(), newVersion);
  completions[0](credential('old'));
  await assert.rejects(first, error => error.code === 'LINE_LOGIN_CANCELLED');
  completions[1](credential('new'));
  assert.equal(await second, 'new');
  manager.logout();
});

test('LIFF RPC uses the current account token and discards a response after logout', async () => {
  const { LineAccountManager } = createLoader()('main/ets/vendors/line/auth/LineAccountManager');
  let finish;
  const requests = [];
  const runner = { cancel() {}, login: async () => credential('mid-1') };
  const transport = { send: async request => {
    requests.push(request);
    return new Promise(resolve => { finish = resolve; });
  } };
  const manager = new LineAccountManager(runner, 'device', 'model', transport);
  await manager.startQrLogin(() => {});
  const pending = manager.sendLiffRpc('issueSubLiffView', new Uint8Array([1, 2]), 'child-id');
  assert.equal(requests[0].path, '/LIFF1');
  assert.equal(requests[0].sessionAccess, 'secret-mid-1');
  assert.equal(requests[0].liffId, 'child-id');
  manager.logout();
  finish(new Uint8Array([3]));
  await assert.rejects(pending, error => error.code === 'LINE_LOGIN_CANCELLED');
});

test('account invalidation notifies all attached sessions once', async () => {
  const { LineAccountManager } = createLoader()('main/ets/vendors/line/auth/LineAccountManager');
  const manager = new LineAccountManager({ cancel() {}, login: async () => credential('mid') }, 'device', 'model');
  await manager.startQrLogin(() => {});
  let first = 0;
  let second = 0;
  const one = () => { first++; };
  manager.addInvalidationListener(one);
  manager.addInvalidationListener(() => { second++; });
  manager.logout();
  assert.equal(first, 1);
  assert.equal(second, 1);
  manager.removeInvalidationListener(one);
  manager.logout();
  assert.equal(first, 1);
  assert.equal(second, 2);
});

test('refresh deadline invalidates the account and closes dependent sessions', async () => {
  const { LineAccountManager } = createLoader()('main/ets/vendors/line/auth/LineAccountManager');
  const manager = new LineAccountManager({ cancel() {}, login: async () => ({
    ...credential('short'), durationUntilRefreshInSec: 1
  }) }, 'device', 'model');
  let invalidations = 0;
  manager.addInvalidationListener(() => { invalidations++; });
  await manager.startQrLogin(() => {});
  await new Promise(resolve => setTimeout(resolve, 1100));
  assert.equal(manager.getAccountId(), undefined);
  assert.equal(invalidations, 1);
  manager.logout();
});
