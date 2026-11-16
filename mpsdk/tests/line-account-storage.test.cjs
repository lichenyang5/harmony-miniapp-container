const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function harness() {
  const values = new Map();
  let fail = '';
  const check = operation => { if (fail === operation) throw { code: 15500000 }; };
  const store = {
    getSync: (key, fallback) => { check('read'); return values.get(key) ?? fallback; },
    putSync: (key, value) => { check('write'); values.set(key, value); },
    deleteSync: key => { check('clear'); values.delete(key); },
    flushSync: () => { check('flush'); }
  };
  const load = createLoader({}, {}, undefined, undefined, undefined, undefined,
    { '@kit.ArkData': { preferences: { getPreferencesSync: () => store } } });
  const { LineAccountManager } = load('main/ets/vendors/line/auth/LineAccountManager');
  let logins = 0;
  const runner = { cancel() {}, login: async () => {
    logins++;
    return { mid: 'user', accessToken: 'access-' + 'x'.repeat(1329), refreshToken: 'refresh',
      certificate: 'cert', loginSessionId: 'session', durationUntilRefreshInSec: 300, metaData: new Map() };
  } };
  return { values, MiniAppError: load('main/ets/core/MiniAppError').MiniAppError,
    logins: () => logins, fail: operation => { fail = operation; },
    // Storage cases focus on refresh outcomes; report ordering/failures have dedicated maintenance tests.
    create: transport => new LineAccountManager(runner, 'model', 'model', transport && { send: request => {
      if (request.method === 'reportRefreshedAccessToken') {
        return Promise.resolve(Uint8Array.from([0x82, 0x41, request.body[2], request.method.length,
          ...Buffer.from(request.method), 0x0c, 0, 0, 0]));
      }
      return transport.send(request);
    } },
      { persistent: true, storageContext: {} }) };
}

test('system Preferences restores credentials larger than 1024 bytes across managers', async () => {
  const h = harness();
  const first = h.create();
  assert.equal(await first.restoreSession(), false);
  await first.startQrLogin(() => {});
  assert.ok([...h.values.values()][0].length > 1329);
  const second = h.create();
  assert.equal(await second.restoreSession(), true);
  assert.equal(second.requireAccessToken(), first.requireAccessToken());
  assert.equal(h.logins(), 1);
  second.logout();
  assert.equal(await h.create().restoreSession(), false);
  first.logout();
});

function refreshRejected(sequence = 2) {
  return Uint8Array.from([0x82, 0x41, sequence, 7, ...Buffer.from('refresh'),
    0x1c, 0x15, 0xd0, 0x0f, 0x16, 4, 0, 0]);
}

function refreshAccepted(sequence = 2) {
  const text = value => [Buffer.byteLength(value), ...Buffer.from(value)];
  return Uint8Array.from([0x82, 0x41, sequence, ...text('refresh'), 0x0c, 0,
    0x18, ...text('restored-access'), 0x16, 0xb0, 9, 0x1c, 0, 0, 0]);
}

function expireStored(h) {
  const key = [...h.values.keys()][0];
  const value = JSON.parse(h.values.get(key));
  value.expiresAt = Date.now() - 1000;
  h.values.set(key, JSON.stringify(value));
}

test('LIFF refresh rejection prevents reusing memory or persisted credentials on the next visit', async t => {
  const h = harness();
  const account = h.create({ send: async request => {
    if (request.method === 'refresh') return refreshRejected();
    const method = 'issueLiffView';
    return Uint8Array.from([0x82, 0x41, 3, method.length, ...Buffer.from(method),
      0x2c, 0x15, 0xee, 1, 0, 0]);
  } });
  t.after(() => account.logout());
  await account.startQrLogin(() => {});
  let invalidations = 0;
  account.addInvalidationListener(() => invalidations++);
  await assert.rejects(account.sendLiffRpc('issueLiffView', new Uint8Array([1]), 'app', 3),
    error => error.code === 'LINE_TOKEN_REFRESH_ERROR_1000_REASON_2');
  assert.equal(account.getAccountId(), undefined);
  assert.equal(invalidations, 1);
  assert.equal(await account.restoreSession(), false);
  assert.equal(await h.create().restoreSession(), false);
  assert.equal(h.logins(), 1); // Only the page may initiate a new QR login.
});

test('restoring expired credentials returns false after a shared terminal refresh rejection', async t => {
  const h = harness();
  const first = h.create();
  t.after(() => first.logout());
  await first.startQrLogin(() => {});
  expireStored(h);
  let refreshes = 0;
  const restored = h.create({ send: async () => { refreshes++; return refreshRejected(); } });
  t.after(() => restored.logout());
  assert.deepEqual(await Promise.all([restored.restoreSession(), restored.restoreSession()]), [false, false]);
  assert.equal(refreshes, 1);
  assert.equal(await restored.restoreSession(), false);
  assert.equal(h.values.size, 0);
});

test('account reads during an expired restore do not cancel its shared refresh', async t => {
  const h = harness();
  const first = h.create();
  t.after(() => first.logout());
  await first.startQrLogin(() => {});
  expireStored(h);
  let complete;
  let refreshes = 0;
  const restored = h.create({ send: () => {
    refreshes++;
    return new Promise(resolve => { complete = resolve; });
  } });
  t.after(() => restored.logout());
  const one = restored.restoreSession();
  const two = restored.restoreSession();
  assert.equal(restored.getAccountId(), undefined);
  assert.throws(() => restored.requireAccessToken(), error => error.code === 'LINE_LOGIN_REQUIRED');
  while (!complete) await new Promise(resolve => setImmediate(resolve));
  assert.equal(refreshes, 1);
  complete(refreshAccepted());
  assert.deepEqual(await Promise.all([one, two]), [true, true]);
  assert.equal(restored.requireAccessToken(), 'restored-access');
});

test('restoring an expired in-memory account does not expose its old token while refreshing', async t => {
  const h = harness();
  let complete;
  const account = h.create({ send: () => new Promise(resolve => { complete = resolve; }) });
  t.after(() => account.logout());
  await account.startQrLogin(() => {});
  expireStored(h);
  account.expiresAt = Date.now() - 1000;
  const pending = account.restoreSession();
  assert.equal(account.getAccountId(), undefined);
  while (!complete) await new Promise(resolve => setImmediate(resolve));
  complete(refreshAccepted());
  assert.equal(await pending, true);
  assert.equal(account.requireAccessToken(), 'restored-access');
});

test('failed storage deletion cannot reload a rejected credential in the same account manager', async t => {
  const h = harness();
  let refreshes = 0;
  const account = h.create({ send: async () => { refreshes++; return refreshRejected(); } });
  t.after(() => { h.fail(''); account.logout(); });
  await account.startQrLogin(() => {});
  h.fail('clear');
  await assert.rejects(account.refreshRejectedToken(account.requireAccessToken(), account.getVersion()));
  assert.ok(h.values.size > 0);
  assert.equal(await account.restoreSession(), false);
  assert.equal(await account.restoreSession(), false);
  assert.equal(refreshes, 1);
});

test('a temporary restore network failure retains credentials for retry', async t => {
  const h = harness();
  const first = h.create();
  t.after(() => first.logout());
  await first.startQrLogin(() => {});
  expireStored(h);
  const restored = h.create({ send: async () => {
    throw new h.MiniAppError('LINE_RPC_NETWORK_FAILED', 'temporary');
  } });
  t.after(() => restored.logout());
  const before = [...h.values.values()][0];
  await assert.rejects(restored.restoreSession(), error => error.code === 'LINE_RPC_NETWORK_FAILED');
  assert.equal([...h.values.values()][0], before);
  await assert.rejects(restored.restoreSession(), error => error.code === 'LINE_RPC_NETWORK_FAILED');
});

test('an old refresh rejection cannot invalidate a replacement login', async t => {
  const h = harness();
  let finish;
  const account = h.create({ send: () => new Promise(resolve => { finish = resolve; }) });
  t.after(() => account.logout());
  await account.startQrLogin(() => {});
  const old = account.refreshRejectedToken(account.requireAccessToken(), account.getVersion());
  const rejected = assert.rejects(old);
  while (!finish) await new Promise(resolve => setImmediate(resolve));
  await account.startQrLogin(() => {});
  const current = account.getVersion();
  finish(refreshRejected());
  await rejected;
  assert.equal(account.getVersion(), current);
  assert.equal(account.getAccountId(), 'user');
  assert.equal(await account.restoreSession(), true);
  assert.ok(h.values.size > 0);
});

test('write and flush failures never reject a successful login or suppress authorized state', async () => {
  for (const operation of ['write', 'flush']) {
    const h = harness();
    const account = h.create();
    const states = [];
    h.fail(operation);
    assert.equal(await account.startQrLogin(state => states.push(state)), 'user');
    assert.equal(account.getAccountId(), 'user');
    assert.equal(states.at(-1).kind, 'authorized');
    assert.equal(account.saveSession(), false);
    h.fail('');
    assert.equal(account.saveSession(), true);
    const restored = h.create();
    assert.equal(await restored.restoreSession(), true);
    restored.logout();
    account.logout();
  }
});

test('unreadable or corrupt Preferences falls back to normal login without throwing', async () => {
  const h = harness();
  const account = h.create();
  h.fail('read');
  assert.equal(await account.restoreSession(), false);
  h.fail('');
  await account.startQrLogin(() => {});
  const key = [...h.values.keys()][0];
  h.values.set(key, '{bad-json');
  assert.equal(await h.create().restoreSession(), false);
  h.fail('clear');
  assert.doesNotThrow(() => account.logout());
  assert.equal(account.getAccountId(), undefined);
});

test('a failed persistence flush does not reject token refresh or the retried LIFF request', async () => {
  const h = harness();
  const str = value => [Buffer.byteLength(value), ...Buffer.from(value)];
  let liffCalls = 0;
  const account = h.create({ send: async request => {
    if (request.method === 'refresh') {
      return Uint8Array.from([0x82, 0x41, request.body[2], ...str('refresh'), 0x0c, 0,
        0x18, ...str('new-access'), 0x16, 0xb0, 9, 0x1c, 0, 0, 0]);
    }
    if (++liffCalls === 1) {
      return Uint8Array.from([0x82, 0x41, 3, ...str('issueLiffView'), 0x2c, 0x15, 0xee, 1, 0, 0]);
    }
    assert.equal(request.sessionAccess, 'new-access');
    return Uint8Array.from([0x82, 0x41, 3, ...str('issueLiffView'), 0x0c, 0, 0, 0]);
  } });
  await account.startQrLogin(() => {});
  h.fail('flush');
  await account.sendLiffRpc('issueLiffView', new Uint8Array([1]), 'app', 3);
  assert.equal(account.requireAccessToken(), 'new-access');
  assert.equal(liffCalls, 2);
  h.fail('');
  account.logout();
});
