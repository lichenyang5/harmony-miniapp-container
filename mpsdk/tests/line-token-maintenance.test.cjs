const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

const report = 'reportRefreshedAccessToken';
const text = value => [Buffer.byteLength(value), ...Buffer.from(value)];
function response(request, failure = false) {
  const fields = failure ? [0x1c, 0x15, 0xd0, 0x0f, 0x16, 4, 0, 0] :
    request.method === report ? [0x0c, 0, 0, 0] :
      [0x0c, 0, 0x18, ...text('new-access'), 0x16, 0xb0, 9, 0x1c, 0,
        0x28, ...text('new-refresh'), 0, 0];
  return Uint8Array.from([0x82, 0x41, request.body[2], ...text(request.method), ...fields]);
}

function setup(send) {
  const values = new Map();
  const storage = { getSync: (key, fallback) => values.get(key) ?? fallback,
    putSync: (key, value) => values.set(key, value), deleteSync: key => values.delete(key), flushSync() {} };
  const load = createLoader({}, {}, undefined, undefined, undefined, undefined,
    { '@kit.ArkData': { preferences: { getPreferencesSync: () => storage } } });
  const { LineAccountManager } = load('main/ets/vendors/line/auth/LineAccountManager');
  let index = 0;
  const runner = { cancel() {}, login: async () => ({ mid: 'user-' + ++index,
    accessToken: 'old-access', refreshToken: 'old-refresh', certificate: '', loginSessionId: '',
    durationUntilRefreshInSec: 300, metaData: new Map() }) };
  const create = () => new LineAccountManager(runner, 'device', 'model', { send },
    { persistent: true, storageContext: {} }, runner);
  return { values, create, account: create() };
}

for (const kind of ['qr', 'email']) {
  test(`${kind} login shares ordered reports, rotation persistence and concurrent refresh`, async t => {
    const calls = [];
    const h = setup(async request => {
      calls.push(request);
      assert.equal(request.path, '/EXT/auth/tokenrefresh/v1');
      if (calls.length === 3) {
        const saved = JSON.parse([...h.values.values()][0]);
        assert.equal(saved.accessToken, 'new-access');
        assert.equal(saved.refreshToken, 'new-refresh');
        assert.equal(h.account.requireAccessToken(), 'new-access');
      }
      return response(request);
    });
    t.after(() => h.account.logout());
    if (kind === 'qr') await h.account.startQrLogin(() => {});
    else await h.account.startEmailLogin('example@example.com', 'password', () => {});
    assert.equal(calls.length, 0); // Initial authentication is separate from token maintenance.
    const version = h.account.getVersion();
    await Promise.all([h.account.refreshRejectedToken('old-access', version),
      h.account.refreshRejectedToken('old-access', version)]);
    assert.deepEqual(calls.map(call => call.method), [report, 'refresh', report]);
    assert.deepEqual(calls.map(call => call.sessionAccess), ['old-access', 'old-access', 'new-access']);
    assert.deepEqual(calls.map(call => call.body[2]), [1, 2, 3]);
    assert.ok(Buffer.from(calls[0].body).includes(Buffer.from('old-access')));
    assert.ok(Buffer.from(calls[1].body).includes(Buffer.from('old-refresh')));
    assert.ok(Buffer.from(calls[2].body).includes(Buffer.from('new-access')));
  });
}

test('pre-report INVALID_REQUEST continues refresh without invalidating the account', async t => {
  const calls = [];
  const h = setup(async request => {
    calls.push(request.method);
    return response(request, calls.length === 1);
  });
  t.after(() => h.account.logout());
  await h.account.startQrLogin(() => {});
  const version = h.account.getVersion();
  await h.account.refreshRejectedToken('old-access', version);
  assert.deepEqual(calls, [report, 'refresh', report]);
  assert.equal(h.account.getVersion(), version);
  assert.equal(h.account.getAccountId(), 'user-1');
  assert.equal(h.account.requireAccessToken(), 'new-access');
  assert.equal(JSON.parse([...h.values.values()][0]).accessToken, 'new-access');
});

test('temporary pre-report failure keeps old credentials and the next attempt can retry', async t => {
  const calls = [];
  const h = setup(async request => {
    calls.push(request.method);
    if (calls.length === 1) throw new Error('offline');
    return response(request);
  });
  t.after(() => h.account.logout());
  await h.account.startQrLogin(() => {});
  const version = h.account.getVersion();
  const stored = [...h.values.values()][0];
  await assert.rejects(h.account.refreshRejectedToken('old-access', version));
  assert.equal(h.account.requireAccessToken(), 'old-access');
  assert.equal([...h.values.values()][0], stored);
  assert.equal(h.account.getVersion(), version);
  await h.account.refreshRejectedToken('old-access', version);
  assert.deepEqual(calls, [report, report, 'refresh', report]);
  assert.equal(h.account.requireAccessToken(), 'new-access');
});

for (const failure of ['service', 'network']) {
  test(`post-report ${failure} failure preserves rotated credentials for restart`, async t => {
    let calls = 0;
    const h = setup(async request => {
      if (++calls === 3) {
        if (failure === 'network') throw new Error('offline');
        return response(request, true);
      }
      return response(request);
    });
    t.after(() => h.account.logout());
    await h.account.startQrLogin(() => {});
    await h.account.refreshRejectedToken('old-access', h.account.getVersion());
    assert.equal(h.account.requireAccessToken(), 'new-access');
    const restored = h.create();
    t.after(() => restored.logout());
    assert.equal(await restored.restoreSession(), true);
    assert.equal(restored.requireAccessToken(), 'new-access');
    assert.equal(calls, 3);
  });
}

for (const stage of [1, 2]) {
  test(`account replacement during maintenance stage ${stage} discards late completion`, async t => {
    const calls = [];
    let complete;
    const h = setup(async request => {
      calls.push(request);
      if (calls.length === stage) return new Promise(resolve => { complete = () => resolve(response(request)); });
      return response(request);
    });
    t.after(() => h.account.logout());
    await h.account.startQrLogin(() => {});
    const pending = h.account.refreshRejectedToken('old-access', h.account.getVersion());
    const rejected = assert.rejects(pending, error => error.code === 'LINE_LOGIN_CANCELLED');
    while (!complete) await new Promise(resolve => setImmediate(resolve));
    await h.account.startEmailLogin('example@example.com', 'password', () => {});
    complete();
    await rejected;
    assert.equal(calls.length, stage);
    assert.equal(h.account.getAccountId(), 'user-2');
    assert.equal(h.account.requireAccessToken(), 'old-access');
    assert.equal(JSON.parse([...h.values.values()][0]).mid, 'user-2');
  });
}

test('post-report does not block refresh, and a rejection of the new token starts a new refresh', async t => {
  const calls = [];
  let complete;
  const h = setup(async request => {
    calls.push(request);
    if (calls.length === 3) return new Promise(resolve => { complete = () => resolve(response(request)); });
    return response(request);
  });
  t.after(() => { complete?.(); h.account.logout(); });
  await h.account.startQrLogin(() => {});
  const version = h.account.getVersion();
  let settled = false;
  const first = h.account.refreshRejectedToken('old-access', version).then(() => { settled = true; });
  while (!complete) await new Promise(resolve => setImmediate(resolve));
  await new Promise(resolve => setImmediate(resolve));
  // A slow best-effort report cannot keep a successful refresh pending.
  assert.equal(settled, true);
  await first;
  await h.account.refreshRejectedToken('new-access', version);
  assert.deepEqual(calls.map(call => call.method), [report, 'refresh', report, report, 'refresh', report]);
  assert.equal(calls[3].sessionAccess, 'new-access');
  assert.ok(Buffer.from(calls[4].body).includes(Buffer.from('new-refresh')));
  complete();
});

test('late background report failure cannot invalidate a replacement login', async t => {
  let complete;
  let calls = 0;
  const h = setup(async request => {
    if (++calls === 3) return new Promise(resolve => { complete = () => resolve(response(request, true)); });
    return response(request);
  });
  t.after(() => { complete?.(); h.account.logout(); });
  await h.account.startQrLogin(() => {});
  const pending = h.account.refreshRejectedToken('old-access', h.account.getVersion());
  while (!complete) await new Promise(resolve => setImmediate(resolve));
  let settled = false;
  pending.then(() => { settled = true; }, () => {});
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(settled, true);
  await pending;
  await h.account.startEmailLogin('example@example.com', 'password', () => {});
  complete();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(h.account.getAccountId(), 'user-2');
  assert.equal(JSON.parse([...h.values.values()][0]).mid, 'user-2');
});

test('new-token rejection before the old refresh settles is not merged into the old task', async t => {
  const calls = [];
  let next;
  const h = setup(async request => {
    calls.push(request.method);
    if (calls.length === 3) {
      // The token is published but the outer refresh promise has not settled yet.
      next = h.account.refreshRejectedToken('new-access', h.account.getVersion());
    }
    return response(request);
  });
  t.after(() => h.account.logout());
  await h.account.startQrLogin(() => {});
  await h.account.refreshRejectedToken('old-access', h.account.getVersion());
  assert.ok(next);
  await next;
  assert.deepEqual(calls, [report, 'refresh', report, report, 'refresh', report]);
});

test('expired restore shares reports and keeps new tokens when post-report fails', async t => {
  const calls = [];
  const h = setup(async request => {
    calls.push(request.method);
    return response(request, calls.length === 1 || calls.length === 3);
  });
  t.after(() => h.account.logout());
  await h.account.startQrLogin(() => {});
  const key = [...h.values.keys()][0];
  const saved = JSON.parse(h.values.get(key));
  saved.expiresAt = Date.now() - 1;
  h.values.set(key, JSON.stringify(saved));
  const restored = h.create();
  t.after(() => restored.logout());
  assert.deepEqual(await Promise.all([restored.restoreSession(), restored.restoreSession()]), [true, true]);
  assert.deepEqual(calls, [report, 'refresh', report]);
  assert.equal(restored.requireAccessToken(), 'new-access');
});
