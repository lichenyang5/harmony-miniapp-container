const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');
const tick = () => new Promise(resolve => setImmediate(resolve));
class ArkURL extends URL { get params() { return this.searchParams; } }

function fixture(enabled = true) {
  const { createLineLiffApiProxyScript } = createLoader()('main/ets/vendors/line/script/LineLiffApiProxyScript');
  const listeners = new Map(), timers = new Map(), posts = [], fetches = [];
  let resolve, reject, count = 0, closed = 0, calls = 0;
  const popup = { closed: false, location: { href: '' }, postMessage: (...args) => posts.push(args), close() { this.closed = true; closed++; } };
  const messages = [{ type: 'text', text: 'test' }];
  const liff = { getContext: () => ({ liffId: '200-test' }), _dispatchEvent() {},
    shareTargetPicker() { calls++; return new Promise((a, b) => { resolve = a; reject = b; }); } };
  const context = { console: { debug() {}, warn() {} }, location: { origin: 'https://app.test' }, URL, AbortController,
    _liff: { postMessage() {} }, liff, open() { return popup; },
    addEventListener: (name, fn) => { const list = listeners.get(name) || []; list.push(fn); listeners.set(name, list); },
    removeEventListener: (name, fn) => listeners.set(name, (listeners.get(name) || []).filter(x => x !== fn)),
    setInterval: fn => { const id = ++count; timers.set(id, fn); return id; }, clearInterval: id => timers.delete(id),
    setTimeout: fn => { const id = ++count; timers.set(id, fn); return id; }, clearTimeout: id => timers.delete(id),
    fetch: async (...args) => { fetches.push(args); return { ok: true, json: async () => ({ status: 'ok' }) }; } };
  context.window = context;
  vm.runInNewContext(createLineLiffApiProxyScript([], enabled).script, context);
  const payload = { liffId: '200-test', ott: 'test-ott', data: JSON.stringify({ messages, isMultiple: true, referrer: { liffId: '200-test', url: 'https://app.test' } }) };
  return { context, liff, popup, messages, payload, posts, fetches, timers, listeners,
    resolve: value => resolve(value), reject: error => reject(error), get calls() { return calls; }, get closed() { return closed; },
    emit: (name, event) => (listeners.get(name) || []).slice().forEach(fn => fn(event)) };
}

test('WEB_HOOK picker consumes one matching payload, validates message source/origin and preserves official result', async () => {
  const f = fixture(); const pending = f.liff.shareTargetPicker(f.messages, { isMultiple: true });
  assert.equal(f.calls, 1);
  const adapter = f.context.__atomicLineSharePicker;
  assert.ok(adapter);
  assert.equal(adapter.accept({ ...f.payload, liffId: 'other' }), false);
  assert.equal(adapter.accept(f.payload), true);
  assert.equal(adapter.accept(f.payload), false);
  assert.match(f.popup.location.href, /^https:\/\/access.line.me\/oauth2\/v2.1\/liff\/shareTargetPicker\?/);
  const good = { origin: 'https://access.line.me', source: f.popup, data: { name: 'receivedHealthcheck' } };
  f.emit('message', { ...good, origin: 'https://evil.test' });
  f.emit('message', { ...good, source: {} }); assert.equal(f.posts.length, 0);
  f.emit('message', good); assert.equal(f.posts[0][0].name, 'ready');
  assert.equal(f.posts[0][1], 'https://access.line.me');
  f.resolve({ status: 'success' }); assert.deepEqual(await pending, { status: 'success' });
  assert.equal(f.closed, 1); assert.equal(f.timers.size, 0); assert.equal(f.listeners.get('message').length, 0);
});

test('picker close posts one cancellation; repeated calls, failure and page exit clean resources', async () => {
  const f = fixture(); const pending = f.liff.shareTargetPicker(f.messages);
  await assert.rejects(f.liff.shareTargetPicker(f.messages)); assert.equal(f.calls, 1);
  f.context.__atomicLineSharePicker.accept(f.payload); f.popup.closed = true;
  for (const fn of [...f.timers.values()].slice(0, 1)) fn();
  await tick(); assert.equal(f.fetches.length, 1); assert.equal(f.fetches[0][1].body, 'result=CANCEL');
  f.resolve(undefined); assert.equal(await pending, undefined); assert.equal(f.timers.size, 0);
  const g = fixture(); const failed = g.liff.shareTargetPicker(g.messages); g.reject(Error('official failed'));
  await assert.rejects(failed, /official failed/); assert.equal(g.closed, 1);
  const h = fixture(); const exited = h.liff.shareTargetPicker(h.messages); h.emit('pagehide', {});
  await assert.rejects(exited); assert.equal(h.timers.size, 0); assert.equal(h.closed, 1);
});

test('default API proxy leaves official share unchanged and only WEB_HOOK registers picker scheme', () => {
  const f = fixture(false); assert.equal(f.context.__atomicLineSharePicker, undefined);
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined, { '@kit.ArkTS': { url: { URL: ArkURL } } });
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  for (const mode of ['web', 'web_hook', 'client']) {
    const session = new MiniAppSession(mode, { info: { vendor: 'line', appId: '200-test', url: 'https://app.test' },
      vendor: new LineVendor(), adapter: new LineAdapter({ mode }), swipeBackController: { dispose() {} } }, {});
    const ids = session.getBinding().createWebSchemeHandlers().map(h => h.id);
    assert.equal(ids.includes('line.share-picker'), mode === 'web_hook');
    assert.equal(session.getBinding().scripts.some(s => s.script.includes('window.__atomicLineSharePicker =')), mode === 'web_hook');
    session.close();
  }
});

test('early close waits for OTT before cancellation, blocked windows do not invoke official sharing', async () => {
  const f = fixture(); const pending = f.liff.shareTargetPicker(f.messages);
  f.popup.closed = true;
  [...f.timers.values()][0](); assert.equal(f.fetches.length, 0);
  assert.equal(f.context.__atomicLineSharePicker.accept(f.payload), true);
  await tick(); assert.equal(f.fetches.length, 1);
  assert.equal(f.fetches[0][1].credentials, undefined);
  f.resolve(undefined); await pending;
  const g = fixture(); g.context.open = () => null;
  await assert.rejects(g.liff.shareTargetPicker(g.messages));
  assert.equal(g.calls, 0); assert.equal(g.timers.size, 0);
});

test('timeout cannot accept a delayed old OTT into a new call while official sharing is pending', async () => {
  const f = fixture(); const pending = f.liff.shareTargetPicker(f.messages);
  [...f.timers.values()][1](); await assert.rejects(pending, /timed out/);
  await assert.rejects(f.liff.shareTargetPicker(f.messages), /already open/);
  assert.equal(f.context.__atomicLineSharePicker.accept(f.payload), false);
  f.resolve(undefined); await tick(); assert.equal(f.timers.size, 0);
  f.popup.closed = false;
  const next = f.liff.shareTargetPicker(f.messages);
  f.resolve(undefined); await next;
  assert.equal(f.calls, 2); assert.equal(f.timers.size, 0);
});

test('synchronous official failure releases its window and permits another call', async () => {
  const f = fixture();
  f.liff.shareTargetPicker = () => { throw Error('official synchronous failure'); };
  await assert.rejects(f.liff.shareTargetPicker(f.messages), /official synchronous failure/);
  assert.equal(f.closed, 1); assert.equal(f.timers.size, 0);
  f.popup.closed = false;
  f.liff.shareTargetPicker = () => Promise.resolve({ status: 'success' });
  assert.deepEqual(await f.liff.shareTargetPicker(f.messages), { status: 'success' });
});

test('unserializable messages reject the Promise rather than throwing synchronously', async () => {
  const f = fixture(); const messages = []; messages.push(messages);
  let pending;
  assert.doesNotThrow(() => { pending = f.liff.shareTargetPicker(messages); });
  await assert.rejects(pending); assert.equal(f.calls, 0); assert.equal(f.timers.size, 0);
});

test('picker scheme rejects stale/subframe/foreign/duplicate parameters and delivers data without evaluating it', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined, { '@kit.ArkTS': { url: { URL: ArkURL } } });
  const { LineSharePickerSchemeHandler } = load('main/ets/vendors/line/scheme/LineSharePickerSchemeHandler');
  const { WebSchemeDecision: D } = load('main/ets/web/scheme/WebSchemeTypes');
  const scripts = [];
  let closed = false, foreground = true;
  const session = { appId: '200-test', isClosed: () => closed, getDocumentId: () => 3,
    lifecycle: { isForeground: () => foreground }, getAdapter: () => ({ getLiffId: () => undefined }), send: async script => scripts.push(script) };
  const handler = new LineSharePickerSchemeHandler(session);
  const data = { messages: [{ type: 'text', text: "');throw Error('injection');//" }], referrer: { liffId: '200-test', url: 'https://app.test' } };
  const params = new URLSearchParams({ liffId: '200-test', ott: 'test-ott', data: JSON.stringify(data), closeModals: 'false' });
  const request = { url: 'line://picker?' + params, isMainFrame: true, documentId: 3 };
  assert.equal(handler.supports(request), true); assert.equal(handler.supports({ url: 'line://app/a' }), false);
  assert.equal(handler.handle(request, {}), D.CONSUME); await tick(); assert.equal(scripts.length, 1);
  let delivered;
  vm.runInNewContext(scripts[0], { window: { __atomicLineSharePicker: { accept: value => { delivered = value; } } } });
  assert.deepEqual(JSON.parse(delivered.data), data);
  for (const update of [{ documentId: 2 }, { isMainFrame: false }, { url: request.url + '&ott=duplicate' },
    { url: request.url + '&liffId=200-test' }, { url: request.url + '&data=duplicate' },
    { url: request.url.replace('ott=test-ott', 'ott=') },
    { url: request.url.replace('200-test', 'other') }, { url: request.url.replace('picker?', 'picker/invalid?') }]) {
    assert.equal(handler.handle({ ...request, ...update }, {}), D.BLOCK);
  }
  foreground = false; assert.equal(handler.handle(request, {}), D.BLOCK);
  foreground = true; closed = true; assert.equal(handler.handle(request, {}), D.BLOCK);
  closed = false; handler.dispose(); assert.equal(handler.handle(request, {}), D.BLOCK);
  assert.equal(scripts.length, 1);
});
