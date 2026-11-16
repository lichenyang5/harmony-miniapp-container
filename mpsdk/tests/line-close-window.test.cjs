const { applicationLifecycle } = require('./application-lifecycle.cjs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');
const flush = () => new Promise(resolve => setImmediate(resolve));
class PlatformURL extends URL { get params() { return this.searchParams; } }
const loader = () => createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
  { '@kit.ArkTS': { url: { URL: PlatformURL } } });

function fixture(load = loader(), id = 'close-test', mode = 'client') {
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  let closed = 0, pendingReply = false, failedReply = false, finishReply;
  const events = [], order = [];
  const session = new MiniAppSession(id, {
    info: { appId: 'same-app', vendor: 'line', url: 'https://app.example/' },
    adapter: new LineAdapter({ mode }), vendor: new LineVendor(),
    swipeBackController: { dispose() {} }, onClose() { closed++; order.push('close'); }
  }, {});
  const window = { _liff: {}, liff: { _dispatchEvent(value) {
    const event = JSON.parse(value);
    events.push(event);
    if (event.type === 'closeWindow') { assert.ok(session.getBinding()); order.push('reply'); }
  } } };
  const host = applicationLifecycle(load);
  host.onAbilityCreate({ context: session.uiAbilityContext });
  host.onAbilityForeground({ context: session.uiAbilityContext });
  session.attach({ evaluate(script) {
    if (failedReply) return Promise.reject(new Error('web execution failed'));
    vm.runInNewContext(script, { window });
    return pendingReply ? new Promise(resolve => { finishReply = resolve; }) : Promise.resolve('');
  } });
  session.beginDocument(session.initialUrl);
  return { session, events, order, window,
    get closed() { return closed; },
    deferReply() { pendingReply = true; }, finishReply() { finishReply(''); },
    rejectReply() { failedReply = true; },
    ready() { session.finishDocument(session.initialUrl); },
    close() { session.getBinding().injections[0].object.postMessage('closeWindow', 'wrong-token', 'close-1', '{"ignored":true}'); },
    navigate(url = 'liff://close', isMainFrame = true, documentId = session.getDocumentId()) {
      return session.interceptWebScheme({ url, isMainFrame, documentId });
    } };
}

test('main closeWindow is advertised, replies with empty data and closes only its own session', async () => {
  const load = loader();
  const f = fixture(load, 'first'), other = fixture(load, 'second');
  f.navigate('liff://app/same-app?feature_token=expected');
  f.ready();
  assert.ok(f.window._liff.features.includes('closeWindow'));
  f.close(); await flush();
  assert.deepEqual(f.events.filter(event => event.type === 'closeWindow'),
    [{ type: 'closeWindow', callbackId: 'close-1', data: {} }]);
  assert.deepEqual(f.order, ['reply', 'close']);
  assert.equal(f.closed, 1);
  assert.ok(other.session.getBinding());
  other.session.close();
});

test('bridge close submits its reply without waiting for webpage evaluation to complete', async () => {
  const f = fixture(); f.ready(); f.deferReply();
  f.close(); await flush();
  assert.equal(f.closed, 1);
  assert.deepEqual(f.order, ['reply', 'close']);
  f.finishReply(); await flush();
});

test('failed webpage reply delivery does not prevent closing the native session', async () => {
  const f = fixture(); f.ready(); f.rejectReply();
  f.close(); await flush();
  assert.equal(f.closed, 1);
  assert.deepEqual(f.order, ['close']);
});

test('main liff close works before ready and app initialization without closing sibling sessions', () => {
  const load = loader();
  const f = fixture(load, 'first'), other = fixture(load, 'second');
  assert.equal(f.navigate('liff://close', false), true);
  assert.equal(f.navigate('liff://close', true, 0), true);
  assert.equal(f.closed, 0);
  assert.equal(f.navigate(), true);
  assert.equal(f.closed, 1);
  assert.deepEqual(f.events, []);
  assert.ok(other.session.getBinding());
  assert.equal(f.navigate(), true);
  assert.equal(f.closed, 1);
  other.session.close();
});

test('repeated bridge close requests cannot repeat the host close notification', async () => {
  const f = fixture(); f.ready();
  f.close(); f.close(); await flush();
  assert.equal(f.closed, 1);
});

test('a reply that synchronously navigates cannot close the replacement document', async () => {
  const f = fixture(); f.ready();
  f.window.liff._dispatchEvent = value => {
    if (JSON.parse(value).type === 'closeWindow') f.session.beginDocument('https://app.example/next');
  };
  f.close(); await flush();
  assert.equal(f.closed, 0);
  assert.ok(f.session.getBinding());
  f.session.close();
});

test('WEB mode keeps browser close behavior and does not install the native close handler', () => {
  const f = fixture(loader(), 'web', 'web');
  assert.deepEqual(f.session.getBinding().injections, []);
  assert.equal(f.navigate(), false);
  assert.equal(f.closed, 0);
  f.session.close();
});
