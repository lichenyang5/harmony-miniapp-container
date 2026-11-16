const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const tick = () => new Promise(resolve => setImmediate(resolve));
class PlatformURL extends URL { get params() { return this.searchParams; } }

function fixture() {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineConsentController } = load('main/ets/vendors/line/liff/LineConsentController');
  const { LineConsentRequiredError } = load('main/ets/vendors/line/liff/LineConsentRequiredError');
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  let version = 1;
  const listeners = new Set();
  const account = { getVersion: () => version, getWebAuthHeaders: () => ({
    'X-Line-Access': 'account-token', 'X-Line-Application': 'same-native-profile' }),
    addInvalidationListener: listener => listeners.add(listener),
    removeInvalidationListener: listener => listeners.delete(listener) };
  const opened = [];
  const presenter = { request(page) {
    let resolve; let reject;
    const result = new Promise((yes, no) => { resolve = yes; reject = no; });
    const request = { result, cancel: () => reject(new MiniAppError('LINE_CONSENT_CANCELLED', 'Cancelled')) };
    opened.push({ page, headers: page.headers, resolve, reject, request });
    return request;
  } };
  return { load, account, opened, listeners, controller: new LineConsentController(presenter),
    error: () => new LineConsentRequiredError('channel', 'https://access.line.me/dialog/consent'),
    invalidate() { version++; for (const listener of listeners) listener(); } };
}

test('consent resumes the original issuance once using native account headers', async () => {
  const f = fixture();
  let calls = 0;
  const view = { url: 'https://app.example', accessToken: 'app-token' };
  const pending = f.controller.run(f.account, async () => {
    if (++calls === 1) throw f.error();
    return view;
  });
  await tick();
  assert.equal(f.opened.length, 1);
  assert.equal(f.opened[0].headers['X-Line-Access'], 'account-token');
  assert.equal(f.opened[0].headers['X-Line-Application'], 'same-native-profile');
  assert.equal(calls, 1);
  f.opened[0].resolve(true);
  assert.equal(await pending, view);
  assert.equal(calls, 2);
  assert.equal(f.listeners.size, 0);
});

test('consent rejection, owner cancellation and account changes cannot retry issuance', async () => {
  for (const action of ['reject', 'cancel', 'account']) {
    const f = fixture(); let calls = 0;
    const pending = f.controller.run(f.account, async () => { calls++; throw f.error(); });
    const failed = assert.rejects(pending, error => error.code === 'LINE_CONSENT_CANCELLED');
    await tick();
    if (action === 'reject') f.opened[0].request.cancel();
    else if (action === 'cancel') f.controller.cancel();
    else f.invalidate();
    await failed;
    f.opened[0].resolve(true); await tick();
    assert.equal(calls, 1);
    assert.equal(f.listeners.size, 0);
  }
});

test('repeated consent response propagates without reopening or looping', async () => {
  const f = fixture(); let calls = 0;
  const pending = f.controller.run(f.account, async () => { calls++; throw f.error(); });
  const failed = assert.rejects(pending, error => error.code === 'LINE_LIFF_ERROR_3');
  await tick();f.opened[0].resolve(true);await failed;
  assert.equal(calls, 2);assert.equal(f.opened.length, 1);
});

test('consent page restricts credential-bearing loads and accepts only official main-frame callbacks', () => {
  const f = fixture();
  const { LineConsentProtocol, LineConsentDecision } = f.load('main/ets/vendors/line/consent/LineConsentProtocol');
  const trusted = 'https://access.line.me/dialog/consent';
  assert.equal(LineConsentProtocol.validateUrl(trusted), trusted);
  for (const address of ['http://access.line.me/', 'https://access.line.me.evil.test/',
    'https://user@access.line.me/', 'https://example.com/', 'https://access.line.me:444/']) {
    assert.throws(() => LineConsentProtocol.validateUrl(address));
  }
  assert.equal(LineConsentProtocol.navigate('lineconnect://allow', true, trusted), LineConsentDecision.ALLOW);
  assert.equal(LineConsentProtocol.navigate('lineconnect://retry', true, trusted), LineConsentDecision.ALLOW);
  assert.equal(LineConsentProtocol.navigate('lineconnect://disallow', true, trusted), LineConsentDecision.DENY);
  assert.equal(LineConsentProtocol.navigate(trusted, true, trusted), LineConsentDecision.LOAD);
  for (const address of ['lineconnect://allow.evil', 'lineconnect://emailregistration', 'javascript:alert(1)']) {
    assert.equal(LineConsentProtocol.navigate(address, true, trusted), LineConsentDecision.BLOCK);
  }
  assert.equal(LineConsentProtocol.navigate('lineconnect://allow', false, trusted), LineConsentDecision.BLOCK);
  assert.equal(LineConsentProtocol.navigate('lineconnect://allow', true, 'https://example.com/'), LineConsentDecision.BLOCK);
});

test('subwindow RPC timeout excludes time spent reading the consent page', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const f = fixture();
  const { LineWindowController } = f.load('main/ets/vendors/line/LineWindowController');
  let calls = 0;
  const shown = []; const errors = [];
  const adapter = { getAccount: () => f.account, issueSubLiffView: async () => {
    if (++calls === 1) throw f.error();
    return { url: 'https://scanner.example/', accessToken: 'child-access', featureToken: 'child-feature',
      contextToken: 'child-context', liffId: 'child-id' };
  } };
  const parent = { id: 'parent', info: {}, getDocumentId: () => 1 };
  const controller = new LineWindowController(parent, adapter, (id, info) => ({ id, info, close() {} }), f.controller);
  controller.attach({ show: child => shown.push(child), hide() {}, reportError: error => errors.push(error) });
  controller.open('liff://subwindow?url=https%3A%2F%2Fliff.line.me%2Fchild-id&msit=ticket', 'verifier');
  await tick();
  assert.equal(f.opened.length, 1);
  t.mock.timers.tick(31000);await tick();
  assert.deepEqual(errors, []);assert.equal(shown.length, 0);
  f.opened[0].resolve(true);await tick();
  assert.equal(calls, 2);assert.equal(shown.length, 1);
  assert.equal(shown[0].info.appId, 'child-id');
  controller.dispose();
});
