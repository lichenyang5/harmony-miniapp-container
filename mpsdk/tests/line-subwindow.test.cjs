const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { applicationLifecycle } = require('./application-lifecycle.cjs');
const vm = require('node:vm');
class PlatformURL extends URL { get params() { return this.searchParams; } }
function loader() {
  return createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
}
const result = { liffId: 'child-id', url: 'https://child.example/path',
  contextToken: 'child-context', accessToken: 'child-access', featureToken: 'child-feature', scopes: ['profile'] };
const flush = () => new Promise(resolve => setImmediate(resolve));

test('window controller delegates child creation and supplies headers independently of vendor bindings', async () => {
  const load = loader();
  const { LineWindowController } = load('main/ets/vendors/line/LineWindowController');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const adapter = new LineAdapter({ issueSubLiffView: async () => result });
  const parent = { id: 'parent', info: {}, uiAbilityContext: {}, getDocumentId: () => 1 };
  const calls = [];
  const shown = [];
  let closed = 0;
  const factory = (id, info, launch) => {
    calls.push({ id, info, launch });
    return { id, close() { closed++; } };
  };
  const controller = new LineWindowController(parent, adapter, factory);
  controller.attach({ show: (child, headers) => shown.push({ child, headers }), hide() {}, reportError: error => { throw error; } });
  controller.open('liff://subwindow?url=https%3A%2F%2Fliff.line.me%2Fchild-id&msit=ticket', 'verifier');
  await flush();
  assert.equal(calls.length, 1);
  assert.equal(shown[0].child.id, calls[0].id);
  assert.deepEqual(shown[0].headers, [{ headerKey: 'X-LINE-LIFF-TOKEN', headerValue: 'child-access' }]);
  assert.equal(calls[0].launch.liffId, 'child-id');
  controller.dispose();
  assert.equal(closed, 1);
});
function fixture(host = { issueSubLiffView: async () => result }) {
  let closed = 0;
  const load = loader();
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const adapter = new LineAdapter({ ...host, mode: 'client' });
  const session = new MiniAppSession('parent', {
    info: { appId: 'parent-id', vendor: 'line', url: 'https://parent.example' },
    adapter, vendor: new LineVendor(), swipeBackController: { dispose() {} }, onClose() { closed++; }
  }, {});
  const lifecycle = applicationLifecycle(load);
  lifecycle.onAbilityCreate({ context: session.uiAbilityContext });
  lifecycle.onAbilityForeground({ context: session.uiAbilityContext });
  session.attach({ evaluate: async () => '', pauseAllMedia() {} });
  session.beginDocument('https://parent.example');
  const binding = session.getBinding();
  const changes = [];
  const errors = [];
  binding.attachWindowHost({ show: child => changes.push(child), hide: () => changes.push(undefined),
    reportError: error => errors.push(error) });
  const navigate = (address = 'liff://subwindow?url=https%3A%2F%2Fliff.line.me%2Fchild-id&msit=ticket') =>
    session.interceptWebScheme({ url: address, isMainFrame: true, documentId: session.getDocumentId() });
  return { session, binding, adapter, changes, errors, navigate, get closed() { return closed; } };
}

// Browser mode is covered by line-mode.test.cjs; client web login is not implemented.
test('a child opened through a Mini App alias uses the issued identity for its bridge', async () => {
  const f = fixture({ issueSubLiffView: async () => ({ ...result, liffId: 'resolved-child' }) });
  f.navigate('liff://subwindow?url=' + encodeURIComponent('https://miniapp.line.me/child-alias') + '&msit=ticket');
  await flush();
  try {
    assert.deepEqual(f.errors, []);
    const child = f.changes.at(-1);
    assert.equal(child.appId, 'child-alias');
    assert.equal(child.getBinding().getAppState().liffId, 'resolved-child');
  } finally { f.session.close(); }
});

test('LINE opens an independent child with its own credentials and the parent verifier', async () => {
  const f = fixture();
  assert.equal(f.navigate(), true);
  await flush();
  const child = f.changes.at(-1);
  assert.ok(child);
  assert.equal(child.appId, 'child-id');
  assert.equal(f.session.appId, 'parent-id');
  const hash = new URLSearchParams(new URL(child.initialUrl).hash.slice(1));
  assert.equal(hash.get('msit'), 'ticket');
  assert.equal(hash.get('mst_verifier'), f.binding.getModalSessionToken().verifier);
  assert.equal(hash.get('access_token'), 'child-access');
  assert.equal(child.getBinding().getAppState().featureToken, 'child-feature');
  assert.match(child.info.customUserAgent, /LIFF\/SubWindow/);
  assert.equal(child.getBinding().getModalSessionToken(), undefined);
  f.navigate(); await flush();
  assert.equal(f.changes.filter(Boolean).length, 1);
  child.attach({ evaluate: async () => '' });
  child.beginDocument(child.initialUrl);
  assert.equal(child.interceptWebScheme({ url: 'liff://close', isMainFrame: true, documentId: child.getDocumentId() }), true);
  assert.equal(f.changes.at(-1), undefined);
  assert.ok(f.session.getBinding());
});

test('late issueSubLiffView result cannot open after parent navigation or disposal', async () => {
  let resolve;
  const f = fixture({ issueSubLiffView: () => new Promise(r => { resolve = r; }) });
  f.navigate();
  f.session.beginDocument('https://parent.example/next');
  resolve(result); await flush();
  assert.equal(f.changes.filter(Boolean).length, 0);
  f.navigate(); f.session.close(); resolve(result); await flush();
  assert.equal(f.changes.filter(Boolean).length, 0);
});

test('missing account provider and invalid schemes report stable errors without opening a child', async () => {
  const f = fixture({});
  f.navigate(); await flush();
  assert.equal(f.errors.at(-1).code, 'LINE_ACCOUNT_PROVIDER_REQUIRED');
  assert.equal(f.changes.filter(Boolean).length, 0);
  f.navigate('liff://subwindow?url=https%3A%2F%2Fevil.example%2Fchild-id&msit=ticket');
  assert.equal(f.errors.at(-1).code, 'LINE_SUBWINDOW_INVALID');
});

test('closing a parent releases only its own child', async () => {
  const a = fixture(); const b = fixture();
  a.navigate(); b.navigate(); await flush();
  const childA = a.changes.at(-1); const childB = b.changes.at(-1);
  a.session.close();
  assert.throws(() => childA.getBinding());
  assert.ok(childB.getBinding());
});

test('child launch retains business query and liff.state while filtering native-only fields', async () => {
  const f = fixture();
  const target = 'https://liff.line.me/child-id?liff.state=%2Fdetail%3Fid%3D1&foo=bar&liff.domain=other&liff.referrer=private';
  f.navigate('liff://subwindow?url=' + encodeURIComponent(target) + '&msit=ticket');
  await flush();
  const child = f.changes.at(-1);
  const address = new URL(child.initialUrl);
  assert.equal(address.searchParams.get('liff.state'), '/detail?id=1');
  assert.equal(address.searchParams.get('foo'), 'bar');
  assert.equal(address.searchParams.has('liff.domain'), false);
  assert.equal(address.searchParams.has('liff.referrer'), false);
  assert.deepEqual(child.getBinding().getInitialHeaders(), [{ headerKey: 'X-LINE-LIFF-TOKEN', headerValue: 'child-access' }]);
});

test('native close removes the child immediately and stores the result once without executing webpage code', async () => {
  const f = fixture(); f.navigate(); await flush();
  const child = f.changes.at(-1);
  const stored = [];
  let finishStore;
  f.adapter.storeSubWindowResult = request => {
    stored.push(request);
    return new Promise(resolve => { finishStore = resolve; });
  };
  child.attach({ evaluate: async () => assert.fail('native close must not depend on child JS readiness') });
  child.beginDocument(child.initialUrl);
  assert.equal(f.binding.requestSubWindowClose(), true);
  assert.equal(f.changes.at(-1), undefined);
  assert.throws(() => child.getBinding());
  assert.equal(f.binding.requestSubWindowClose(), false);
  assert.deepEqual(stored, [{ liffId: 'child-id', msit: 'ticket',
    mstVerifier: f.binding.getModalSessionToken().verifier }]);
  finishStore();
  await flush();
  assert.equal(stored.length, 1);
  assert.deepEqual(f.errors, []);
  f.session.close();
});

test('late native result-store failures cannot close or report UI errors to a replacement child', async () => {
  const f = fixture(); f.navigate(); await flush();
  let rejectStore;
  f.adapter.storeSubWindowResult = () => new Promise((_resolve, reject) => { rejectStore = reject; });
  f.binding.requestSubWindowClose();
  f.navigate(); await flush();
  const current = f.changes.at(-1);
  rejectStore(new Error('private result failure'));
  await flush();
  assert.equal(f.changes.at(-1), current);
  assert.ok(current.getBinding());
  assert.deepEqual(f.errors, []);
  f.adapter.storeSubWindowResult = async () => {};
  f.session.close();
});

test('child bridge close replies before removing the child and cannot remove the parent', async () => {
  const f = fixture(); f.navigate(); await flush();
  const child = f.changes.at(-1);
  const events = [];
  let stored = 0;
  f.adapter.storeSubWindowResult = async () => { stored++; };
  const window = { _liff: {}, liff: { _dispatchEvent: json => {
    assert.ok(child.getBinding());
    events.push(JSON.parse(json));
  } } };
  child.attach({ evaluate: async script => { vm.runInNewContext(script, { window }); return ''; } });
  child.beginDocument(child.initialUrl);
  child.finishDocument(child.initialUrl);
  const proxy = child.getBinding().injections[0].object;
  proxy.postMessage('closeWindow', '', 'close-1', '{}');
  await flush();
  assert.equal(events.at(-1).callbackId, 'close-1');
  assert.deepEqual(events.at(-1).data, {});
  assert.equal(f.changes.at(-1), undefined);
  assert.ok(f.session.getBinding());
  assert.equal(stored, 1);
});

test('parent bridge close releases its child and stores its result once before notifying the host', async () => {
  const f = fixture(); f.navigate(); await flush();
  const child = f.changes.at(-1);
  let stored = 0;
  f.adapter.storeSubWindowResult = async () => { stored++; };
  f.session.finishDocument(f.session.initialUrl);
  f.binding.injections[0].object.postMessage('closeWindow', '', 'parent-close', '{}');
  await flush();
  assert.equal(f.closed, 1);
  assert.equal(stored, 1);
  assert.equal(f.changes.at(-1), undefined);
  assert.throws(() => child.getBinding());
  assert.throws(() => f.session.getBinding());
});

test('closing an old child after account replacement cannot submit its ticket as the new account', async () => {
  for (const change of ['version', 'account']) {
    const load = loader();
    const { LineWindowController } = load('main/ets/vendors/line/LineWindowController');
    let version = 1;
    let account = { getVersion: () => version };
    let stored = 0;
    let closed = 0;
    const shown = [];
    const controller = new LineWindowController({ id: 'parent', info: {}, getDocumentId: () => 1 }, {
      getAccount: () => account,
      issueSubLiffView: async () => result,
      storeSubWindowResult: async () => { stored++; }
    }, id => ({ id, close() { closed++; } }));
    controller.attach({ show: child => shown.push(child), hide: () => shown.push(undefined), reportError() {} });
    controller.open('liff://subwindow?url=https%3A%2F%2Fliff.line.me%2Fchild-id&msit=ticket', 'verifier');
    await flush();
    if (change === 'version') version++;
    else account = { getVersion: () => version };
    assert.equal(controller.requestClose(), true);
    await flush();
    assert.equal(closed, 1);
    assert.equal(shown.at(-1), undefined);
    assert.equal(stored, 0, change);
    controller.dispose();
  }
});

test('raw transport receives an official Compact request; host failures and invalid child data do not leak', async () => {
  const load = loader();
  const { LineSubViewService } = load('main/ets/vendors/line/liff/LineSubViewService');
  let sent;
  const service = new LineSubViewService({ sendLiffRpc: async request => { sent = request; throw new Error('private credential'); } });
  await assert.rejects(service.issue({ liffId: 'child-id', msit: 'ticket', requestedUrl: 'https://liff.line.me/child-id' }),
    e => e.code === 'LINE_SUBVIEW_FAILED' && !e.message.includes('credential'));
  assert.equal(sent.method, 'issueSubLiffView');
  assert.equal(sent.path, '/LIFF1');
  assert.equal(sent.body[0], 0x82);
  for (const invalid of [{ ...result, accessToken: '' }, { ...result, accessToken: true },
    { ...result, scopes: [123] }, { ...result, idToken: 123 }, { ...result, liffId: '' }, { ...result, liffId: 123 },
    { ...result, url: 'http://insecure.example' }]) {
    const f = fixture({ issueSubLiffView: async () => invalid });
    f.navigate(); await flush();
    assert.equal(f.errors.at(-1).code, 'LINE_SUBVIEW_INVALID');
    assert.equal(f.changes.filter(Boolean).length, 0);
  }
});

test('LINE adapter creates independent navigation that discovers its binding through the active endpoint', async () => {
  const f = fixture(); f.navigate(); await flush();
  const child = f.changes.at(-1);
  child.attach({ evaluate: async () => '' });
  child.beginDocument(child.initialUrl);
  let historyCalls = 0;
  const endpoint = { session: f.session, controller: {
    accessBackward() { historyCalls++; return false; }
  } };
  const nav = f.adapter.createNavigationController();
  const other = f.adapter.createNavigationController();
  assert.notEqual(nav, other);
  nav.attach(endpoint);
  assert.equal(nav.goBack(), true);
  assert.equal(historyCalls, 0);
  assert.equal(other.goBack(), false);
  child.interceptWebScheme({ url: 'liff://close', isMainFrame: true, documentId: child.getDocumentId() });
  assert.equal(nav.goBack(), false);
  assert.equal(historyCalls, 1);
  nav.detach(endpoint);
  assert.equal(nav.goBack(), false);
});

test('detaching an old LINE overlay cannot release the current overlay child; current detach releases it', async () => {
  const f = fixture();
  const old = { show() {}, hide() {}, reportError() {} };
  const shown = [];
  const current = { show: child => shown.push(child), hide() {}, reportError() {} };
  f.binding.attachWindowHost(old);
  f.binding.attachWindowHost(current);
  f.navigate(); await flush();
  const child = shown.at(-1);
  f.binding.detachWindowHost(old);
  assert.ok(child.getBinding());
  f.binding.detachWindowHost(current);
  assert.throws(() => child.getBinding());
  assert.ok(f.session.getBinding());
});
