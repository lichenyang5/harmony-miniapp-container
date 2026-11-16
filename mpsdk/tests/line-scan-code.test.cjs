const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');
const { applicationLifecycle } = require('./application-lifecycle.cjs');
const { createTestSession } = require('./test-session.cjs');
const flush = () => new Promise(resolve => setImmediate(resolve));
class PlatformURL extends URL { get params() { return this.searchParams; } }

function environment(t, supported = true) {
  const calls = [], sessions = [], hosts = new Set();
  let scan = async () => ({ originalValue: 'raw-code' });
  const load = createLoader(undefined, {
    startScanForResult(host, options) { calls.push({ host, options }); return scan(); }
  }, undefined, undefined, capability =>
    capability !== 'SystemCapability.Multimedia.Scan.ScanBarcode' || supported, undefined,
  { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const lifecycle = applicationLifecycle(load);
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  function host() {
    const context = { applicationInfo: { accessTokenId: 1 } };
    hosts.add(context);
    lifecycle.onAbilityCreate({ context });
    lifecycle.onAbilityForeground({ context });
    return context;
  }
  function create({ context = host(), child = false, mode = 'client' } = {}) {
    const launch = child ? { liffId: 'same-app', result: {
      url: 'https://app.example/', featureToken: 'token'
    }, msit: 'ticket', verifier: 'verifier', onClose() {} } : undefined;
    const session = new MiniAppSession(`line-scan-${sessions.length}`, {
      info: { appId: 'same-app', vendor: 'line', url: 'https://app.example/' },
      adapter: new LineAdapter({ mode }), vendor: new LineVendor(launch),
      swipeBackController: { dispose() {} }
    }, context);
    sessions.push(session);
    const events = [], window = { _liff: {}, liff: {
      _dispatchEvent(json) { events.push(JSON.parse(json)); }
    } };
    session.attach({ async evaluate(script) { vm.runInNewContext(script, { window }); return ''; } });
    const binding = session.getBinding();
    const proxy = binding.injections[0]?.object;
    session.beginDocument(session.initialUrl);
    if (!child) session.interceptWebScheme({
      url: 'liff://app/same-app?feature_token=token', isMainFrame: true,
      documentId: session.getDocumentId()
    });
    session.finishDocument(session.initialUrl);
    return { session, binding, context, window, proxy, events,
      replies: () => events.filter(event => event.type === 'scanCode'),
      request(id = 'scan', token = 'token', params = '{}') {
        proxy.postMessage('scanCode', token, id, params);
      }
    };
  }
  t.after(() => {
    sessions.forEach(session => session.close());
    hosts.forEach(context => lifecycle.onAbilityDestroy({ context }));
  });
  return { load, lifecycle, calls, host, create, setScan(value) { scan = value; } };
}

test('native main and child advertise scanCode and return raw QR text with the original callback', async t => {
  const e = environment(t);
  const value = ' https://example.com/?q="\\\n\u2028 ';
  e.setScan(async () => ({ originalValue: value }));
  for (const child of [false, true]) {
    const f = e.create({ child });
    assert.ok(f.window._liff.features.includes('scanCode'));
    f.request('opaque-id', 'token', '{"scanType":"ALL","ignored":true}');
    await flush();
    assert.deepEqual(f.replies(), [{ type: 'scanCode', callbackId: 'opaque-id', data: { value } }]);
    assert.equal(e.calls.at(-1).host, f.context);
    assert.deepEqual(e.calls.at(-1).options, {
      scanTypes: [11], enableMultiMode: false, enableAlbum: true
    });
  }
});

test('user cancellation returns empty data and allows another scan', async t => {
  const e = environment(t), f = e.create();
  e.setScan(async () => { throw { code: 1000500002, message: 'private' }; });
  f.request('cancel'); await flush();
  assert.deepEqual(f.replies(), [{ type: 'scanCode', callbackId: 'cancel', data: {} }]);
  e.setScan(async () => ({ originalValue: 'retry' }));
  f.request('retry'); await flush();
  assert.deepEqual(f.replies().at(-1).data, { value: 'retry' });
});

test('native failures and invalid results return sanitized INTERNAL_ERROR', async t => {
  const e = environment(t), f = e.create();
  for (const scan of [
    async () => { throw { code: 1000500001, message: 'private token' }; },
    async () => ({ originalValue: '' }),
    async () => ({ originalValue: null })
  ]) {
    e.setScan(scan); f.request(); await flush();
    assert.deepEqual(f.replies().at(-1).error, { code: 'INTERNAL_ERROR', description: 'Internal error' });
  }
});

test('wrong tokens, inactive documents and WEB mode never start the native reader', async t => {
  const e = environment(t), f = e.create();
  f.request('bad-token', 'wrong'); await flush();
  assert.equal(f.replies()[0].error.code, 'NO_AUTHORITY');
  f.session.beginDocument('https://app.example/next');
  f.request('not-ready'); await flush();
  assert.equal(f.replies().length, 1);
  const web = e.create({ mode: 'web' });
  assert.deepEqual(web.binding.injections, []);
  assert.equal(web.window._liff.features, undefined);
  assert.equal(e.calls.length, 0);
});

test('unsupported platforms and background hosts reject scans; destroyed hosts ignore stale proxies', async t => {
  const unsupported = environment(t, false), a = unsupported.create();
  a.request(); await flush();
  assert.equal(a.replies()[0].error.code, 'INTERNAL_ERROR');
  assert.equal(unsupported.calls.length, 0);
  const e = environment(t), f = e.create();
  e.lifecycle.onAbilityBackground({ context: f.context });
  f.request('background'); await flush();
  assert.equal(f.replies()[0].error.code, 'PERMISSION_DENIED');
  assert.equal(e.calls.length, 0);
  e.lifecycle.onAbilityForeground({ context: f.context });
  f.request('foreground'); await flush();
  assert.deepEqual(f.replies().at(-1).data, { value: 'raw-code' });
  const replies = f.replies().length;
  const scans = e.calls.length;
  e.lifecycle.onAbilityDestroy({ context: f.context });
  assert.equal(f.session.lifecycle.getState(), 'DESTROYED');
  f.request('destroyed'); await flush();
  assert.equal(f.replies().length, replies);
  assert.equal(e.calls.length, scans);
});

test('repeated requests and same-app siblings cannot replace the active callback', async t => {
  const e = environment(t), a = e.create(), b = e.create({ context: a.context });
  let finish;
  e.setScan(() => new Promise(resolve => { finish = resolve; }));
  a.request('first'); a.request('duplicate'); b.request('sibling'); await flush();
  assert.equal(e.calls.length, 1);
  assert.equal(a.replies()[0].callbackId, 'duplicate');
  assert.equal(a.replies()[0].error.code, 'INTERNAL_ERROR');
  assert.equal(b.replies()[0].error.code, 'INTERNAL_ERROR');
  finish({ originalValue: 'first-result' }); await flush();
  assert.deepEqual(a.replies().at(-1), {
    type: 'scanCode', callbackId: 'first', data: { value: 'first-result' }
  });
  e.setScan(async () => ({ originalValue: 'second-result' }));
  a.session.close(); b.request('second'); await flush();
  assert.deepEqual(b.replies().at(-1).data, { value: 'second-result' });
});

test('navigation and disposal drop late success/cancellation and keep native occupancy until completion', async t => {
  for (const close of [false, true]) {
    for (const cancel of [false, true]) {
      const e = environment(t), a = e.create(), b = e.create({ context: a.context });
      let finish, reject;
      e.setScan(() => new Promise((resolve, fail) => { finish = resolve; reject = fail; }));
      a.request('old');
      if (close) a.session.close();
      else {
        a.session.beginDocument('https://app.example/next');
        a.session.finishDocument('https://app.example/next');
      }
      b.request('busy'); await flush();
      assert.equal(e.calls.length, 1);
      assert.equal(b.replies()[0].error.code, 'INTERNAL_ERROR');
      if (cancel) reject({ code: 1000500002 });
      else finish({ originalValue: 'late' });
      await flush();
      assert.deepEqual(a.replies(), []);
      e.setScan(async () => ({ originalValue: 'new' }));
      b.request('new'); await flush();
      assert.deepEqual(b.replies().at(-1).data, { value: 'new' });
    }
  }
});

test('LINE and VK share scanner occupancy while VK retains ALL scan types', async t => {
  const e = environment(t), f = e.create(), events = [];
  const vk = createTestSession(e.load, { host: f.context, onScript(script) {
    vm.runInNewContext(script, { window: { atomicBridge: {
      postResponse(_id, event) { events.push(JSON.parse(JSON.stringify(event))); }
    } } });
  } });
  t.after(() => vk.close());
  const requestVk = () => vk.getBinding().injections[0].object.onInterceptRequest(JSON.stringify({
    type: 'vk-connect', handler: 'VKWebAppOpenCodeReader', params: { request_id: 42 }
  }), 'vk-route');
  let finish;
  e.setScan(() => new Promise(resolve => { finish = resolve; }));
  f.request(); requestVk(); await flush();
  assert.equal(e.calls.length, 1);
  assert.equal(events[0].type, 'VKWebAppOpenCodeReaderFailed');
  finish({ originalValue: 'line' }); await flush();
  e.setScan(async () => ({ originalValue: 'vk' }));
  requestVk(); await flush();
  assert.deepEqual(events.at(-1), {
    type: 'VKWebAppOpenCodeReaderResult', data: { code_data: 'vk', request_id: 42 }
  });
  assert.deepEqual(e.calls.at(-1).options.scanTypes, [0]);
});
