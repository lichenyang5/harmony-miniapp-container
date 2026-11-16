const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function credential(mid = 'email-mid') {
  return { mid, accessToken: 'access', refreshToken: 'refresh', certificate: '',
    loginSessionId: 'session', durationUntilRefreshInSec: 300, metaData: new Map() };
}
function managerWith(emailRunner, overrides = {}, options) {
  const { LineAccountManager } = createLoader({}, {}, undefined, {}, undefined, undefined, overrides)
    ('main/ets/vendors/line/auth/LineAccountManager');
  return new LineAccountManager({ cancel() {}, login: async () => credential('qr') },
    'device', 'model', undefined, options, emailRunner);
}

test('email login publishes the account only after final authentication and survives UI callback errors', async () => {
  let complete;
  const events = [];
  const manager = managerWith({ cancel() {}, login: async (email, password, system, model, onState) => {
    assert.deepEqual([email, password, system, model], ['a@example.com', ' pass ', 'device', 'model']);
    onState({ kind: 'pinReady', pin: '123456' });
    return new Promise(resolve => { complete = resolve; });
  } });
  const pending = manager.startEmailLogin('a@example.com', ' pass ', state => {
    events.push(state.kind);
    throw new Error('UI failure');
  });
  assert.equal(manager.getAccountId(), undefined);
  complete(credential());
  assert.equal(await pending, 'email-mid');
  assert.equal(manager.requireAccessToken(), 'access');
  assert.equal(events.at(-1), 'authorized');
  manager.logout();
});

test('email login cancellation and replacement reject old results without publishing credentials', async () => {
  const finishes = [];
  let cancelled = 0;
  const manager = managerWith({ cancel() { cancelled++; },
    login: async () => new Promise(resolve => finishes.push(resolve)) });
  const old = manager.startEmailLogin('a', 'p', () => {});
  manager.cancelLogin();
  const current = manager.startEmailLogin('b', 'p', () => {});
  finishes[0](credential('stale'));
  await assert.rejects(old, error => error.code === 'LINE_LOGIN_CANCELLED');
  finishes[1](credential('current'));
  await current;
  assert.equal(manager.getAccountId(), 'current');
  assert.ok(cancelled > 0);
  manager.logout();
});

test('QR replacement cancels pending email while cancelQrLogin leaves an email attempt active', async () => {
  let finish;
  const manager = managerWith({ cancel() {}, login: async () => new Promise(resolve => { finish = resolve; }) });
  const pending = manager.startEmailLogin('a', 'p', () => {});
  const generation = manager.getVersion();
  manager.cancelQrLogin();
  assert.equal(manager.getVersion(), generation);
  await manager.startQrLogin(() => {});
  finish(credential());
  await assert.rejects(pending, error => error.code === 'LINE_LOGIN_CANCELLED');
  assert.equal(manager.getAccountId(), 'qr');
  manager.logout();
});

test('invalid email input does not discard a usable account', async () => {
  const manager = managerWith({ cancel() {}, login: async () => credential() });
  await manager.startQrLogin(() => {});
  await assert.rejects(manager.startEmailLogin('', 'p', () => {}),
    error => error.code === 'LINE_EMAIL_INVALID_ARGUMENT');
  assert.equal(manager.getAccountId(), 'qr');
  manager.logout();
});

test('email persistence failure does not prevent authorized state or in-memory reuse', async () => {
  const events = [];
  const manager = managerWith({ cancel() {}, login: async () => credential() }, {
    '@kit.ArkData': { preferences: { getPreferencesSync() { throw new Error('disk failed'); } } }
  }, { persistent: true, storageContext: {} });
  await manager.startEmailLogin('a', 'p', state => events.push(state.kind));
  assert.equal(await manager.restoreSession(), true);
  assert.equal(events.at(-1), 'authorized');
  manager.logout();
});

test('email credentials use versioned secondary-ready storage without email or password', async t => {
  const values = new Map();
  const overrides = { '@kit.ArkData': { preferences: { getPreferencesSync: () => ({
    getSync: (key, fallback) => values.get(key) ?? fallback,
    putSync: (key, value) => values.set(key, value), deleteSync: key => values.delete(key), flushSync() {}
  }) } } };
  const options = { persistent: true, storageContext: {} };
  const runner = { cancel() {}, login: async () => credential() };
  const first = managerWith(runner, overrides, options);
  const second = managerWith({ cancel() {}, login: () => assert.fail('restore must not authenticate') }, overrides, options);
  t.after(() => { first.logout(); second.logout(); });
  await first.startEmailLogin('private-email', 'private-password', () => {});
  const raw = [...values.values()][0];
  assert.equal(JSON.parse(raw).version, 2);
  assert.equal(JSON.parse(raw).role, 'SECONDARY');
  assert.equal(JSON.parse(raw).stage, 'ready');
  assert.equal(raw.includes('private-email'), false);
  assert.equal(raw.includes('private-password'), false);
  assert.equal(await second.restoreSession(), true);
  assert.equal(second.getAccountId(), 'email-mid');
});
