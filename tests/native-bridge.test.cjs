const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { createLoader } = require('../mpsdk/tests/sdk-loader.cjs');
const { applicationLifecycle } = require('../mpsdk/tests/application-lifecycle.cjs');
const { createTestSession } = require('../mpsdk/tests/test-session.cjs');
const flush = () => new Promise(resolve => setImmediate(resolve));
class PlatformURL extends URL { get params() { return this.searchParams; } }

function lineFixture(t) {
  let scan = async () => ({ originalValue: 'qr-result' });
  const calls = [];
  const load = createLoader(undefined, {
    startScanForResult(host, options) { calls.push(options); return scan(); }
  }, undefined, undefined, () => true, undefined,
  { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const host = { applicationInfo: { accessTokenId: 1 } };
  const lifecycle = applicationLifecycle(load);
  lifecycle.onAbilityCreate({ context: host });
  lifecycle.onAbilityForeground({ context: host });
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const session = new MiniAppSession('line-web-migration', {
    info: { vendor: 'line', appId: '123-abc', url: 'https://liff.line.me/123-abc' },
    vendor: new LineVendor(), adapter: new LineAdapter({ mode: 'web' }),
    swipeBackController: { dispose() {} }
  }, host);
  const events = [];
  const window = { liff: { getContext: () => ({ liffId: '123-abc' }),
    _dispatchEvent: json => events.push(JSON.parse(json)) } };
  const context = vm.createContext({ window, console: { debug() {} } });
  session.attach({ async evaluate(script) { vm.runInContext(script, context); return ''; } });
  session.beginDocument(session.initialUrl);
  const proxy = session.getBinding().injections[0].object;
  window._liff = { postMessage: (...args) => proxy.postMessage(...args) };
  session.finishDocument(session.initialUrl);
  const { createLineLiffApiProxyScript } = load('main/ets/vendors/line/script/LineLiffApiProxyScript');
  vm.runInContext(createLineLiffApiProxyScript(['scanCodeV2']).script, context);
  events.length = 0; // Ignore the SDK's document-ready feature publication.
  t.after(() => { session.close(); lifecycle.onAbilityDestroy({ context: host }); });
  return { session, window, calls, events, setScan: next => { scan = next; } };
}

test('LINE WEB official API proxy reaches native scanner and resolves the same request', async t => {
  const f = lineFixture(t);
  const result = await f.window.liff.scanCodeV2();
  assert.equal(result.value, 'qr-result');
  assert.equal(f.calls.length, 1);
  assert.deepEqual(f.calls[0].scanTypes, [11]);
  assert.equal(f.events.length, 0); // Proxy consumes the callback rather than the official fallback.
});

test('LINE WEB cancel rejects honestly and the next scan succeeds', async t => {
  const f = lineFixture(t);
  f.setScan(async () => { throw { code: 1000500002 }; });
  await assert.rejects(f.window.liff.scanCodeV2(), error => error.code === 'UNKNOWN');
  f.setScan(async () => ({ originalValue: 'retry' }));
  assert.equal((await f.window.liff.scanCodeV2()).value, 'retry');
});

test('LINE WEB navigation drops a late native result', async t => {
  const f = lineFixture(t);
  let finish;
  f.setScan(() => new Promise(resolve => { finish = resolve; }));
  let delivered = false;
  f.window.liff.scanCodeV2().then(() => { delivered = true; }, () => { delivered = true; });
  f.session.beginDocument('https://example.com/next');
  finish({ originalValue: 'late' });
  await flush();
  assert.equal(delivered, false);
  assert.equal(f.events.length, 0);
});

test('VK scan and haptic requests preserve IDs; web auth remains a pass-through', async t => {
  const load = createLoader(undefined, { startScanForResult: async () => ({ originalValue: 'vk-qr' }) });
  const { HapticTools } = load('main/ets/capabilities/haptic/HapticTools');
  const effects = [];
  HapticTools.vibrate = async config => effects.push(config);
  const replies = [];
  const session = createTestSession(load, { onScript: script => {
    vm.runInNewContext(script, { window: { atomicBridge: {
      postResponse: (route, event) => replies.push({ route, event })
    } } });
  } });
  const lifecycle = applicationLifecycle(load);
  lifecycle.onAbilityCreate({ context: session.uiAbilityContext });
  lifecycle.onAbilityForeground({ context: session.uiAbilityContext });
  t.after(() => { session.close(); lifecycle.onAbilityDestroy({ context: session.uiAbilityContext }); });
  const proxy = session.getBinding().injections[0].object;
  const request = (handler, params = {}) => proxy.onInterceptRequest(JSON.stringify({
    type: 'vk-connect', handler, params: { ...params, request_id: 42 }
  }), 'original-frame');
  request('VKWebAppOpenCodeReader'); await flush();
  assert.equal(replies[0].route, 'original-frame');
  assert.equal(replies[0].event.data.request_id, 42);
  assert.equal(replies[0].event.data.code_data, 'vk-qr');
  request('VKWebAppTapticImpactOccurred', { style: 'light' }); await flush();
  assert.equal(effects.length, 1);
  assert.equal(replies[1].event.data.result, true);
  request('VKWebAppTapticImpactOccurred', { style: 'invalid' }); await flush();
  assert.equal(replies[2].event.data.error_data.error_code, 5);
  assert.equal(request('VKWebAppGetAuthToken').intercept, false);
});
