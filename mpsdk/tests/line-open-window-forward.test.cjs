const { applicationLifecycle } = require('./application-lifecycle.cjs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
class PlatformURL extends URL { get params() { return this.searchParams; } }
const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
  { '@kit.ArkTS': { url: { URL: PlatformURL } } });
const context = overrides => ({ getDocumentId: () => 1, addCleanup() {}, ...overrides });
const presenter = overrides => ({ async open() {}, dismissAll() {}, dispose() {}, ...overrides });

// Substitute browser effects in an isolated module loader, keeping production constructors unchanged.
function createHandler(context, browser = presenter()) {
  const isolated = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineBrowserHost } = isolated('main/ets/vendors/line/browser/LineBrowserHost');
  LineBrowserHost.prototype.open = address => browser.open(address);
  LineBrowserHost.prototype.dismissAll = () => browser.dismissAll();
  LineBrowserHost.prototype.dispose = () => browser.dispose();
  const { LineOpenWindowHandler } = isolated('main/ets/vendors/line/handlers/LineOpenWindowHandler');
  return new LineOpenWindowHandler(context, new LineBrowserHost({}));
}

test('an alias owner forwards the parsed target ID and URL for the host to resolve reuse', async () => {
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineOpenWindowHandler } = load('main/ets/vendors/line/handlers/LineOpenWindowHandler');
  const alias = 'buruburudobutsu', canonical = '2007326019-vAg8J6Bp', opened = [];
  const string = value => [Buffer.byteLength(value), ...Buffer.from(value)];
  const account = { restoreSession: async () => true, getVersion: () => 1,
    addInvalidationListener() {}, removeInvalidationListener() {},
    sendLiffRpc: async () => Uint8Array.from([0x82, 0x41, 1, ...string('issueLiffView'), 0x0c, 0,
      0x1c, 0x28, ...string('https://app.example/'), 0,
      0x18, ...string('context'), 0x18, ...string('access'), 0x18, ...string('feature'),
      0xb8, ...string(canonical), 0, 0]) };
  const adapter = new LineAdapter({ mode: 'client', account });
  const session = new MiniAppSession('alias-self-open', {
    info: { appId: alias, vendor: 'line', url: `https://miniapp.line.me/${alias}` },
    adapter, vendor: new LineVendor(), swipeBackController: { dispose() {} },
    onOpenMiniApp: async app => opened.push(app)
  }, {});
  session.attach({ evaluate: async () => '' }); session.lifecycle.setHostForeground(true);
  const handler = new LineOpenWindowHandler(session, session.getBinding().browser);
  try {
    await session.getBinding().prepareInitialLoad();
    for (const id of [canonical, alias, 'another-app']) {
      await handler.handle({ url: `https://miniapp.line.me/${id}/detail?x=1&x=2#section` }, {});
    }
    assert.deepEqual(opened.map(app => app.appId), [canonical, alias, 'another-app']);
    assert.equal(opened[0].url, `https://miniapp.line.me/${canonical}?liff.state=` +
      encodeURIComponent('/detail?x=1&x=2#section'));
    assert.equal(adapter.getLiffId(session), canonical);
  } finally { handler.dispose(); session.close(); }
});

test('only internal LIFF targets are forwarded; ordinary and external URLs use embedded browser', async () => {
  const apps = [], browsed = [];
  const handler = createHandler(context({ async requestOpenMiniApp(app) { apps.push(app); } }),
    presenter({ async open(url) { browsed.push(url); } }));
  assert.deepEqual(await handler.handle({ url: 'https://miniapp.line.me/123/a?x=1&x=2#b' }, {}), {});
  assert.equal(apps.length, 1);
  assert.equal(apps[0].appId, '123'); assert.equal(apps[0].vendor, 'line');
  assert.equal(new URL(apps[0].url).searchParams.get('liff.state'), '/a?x=1&x=2#b');
  await handler.handle({ url: 'https://example.com' }, {});
  await handler.handle({ url: 'https://liff.line.me/123', external: true }, {});
  assert.equal(apps.length, 1);
  assert.deepEqual(browsed, ['https://example.com', 'https://liff.line.me/123']);
});

test('forwarding is awaited; absent host callback fails without creating target sessions', async () => {
  let resolve, completed = false;
  const browser = presenter();
  const handler = createHandler({ requestOpenMiniApp: () => new Promise(done => { resolve = done; }) }, browser);
  const pending = handler.handle({ url: 'https://liff.line.me/123' }, {}).then(value => { completed = true; return value; });
  await Promise.resolve(); assert.equal(completed, false);
  resolve(); assert.deepEqual(await pending, {});
  const missing = createHandler(context(), browser);
  await assert.rejects(missing.handle({ url: 'https://liff.line.me/123' }, {}), error => error.toData().code === 'INVALID_ARGUMENT');
  handler.dispose(); handler.dispose();
  await assert.rejects(handler.handle({ url: 'https://liff.line.me/123' }, {}));
});

test('invalid arguments never invoke host or browser; host errors are sanitized', async () => {
  let calls = 0;
  const handler = createHandler(context({ async requestOpenMiniApp() { calls++; throw new Error('private token'); } }),
    presenter({ async open() { calls++; } }));
  for (const params of [{}, { url: null }, { url: '' }, { url: 2 }, { url: 'https://a', external: null },
    { url: 'javascript:alert(1)' }, { url: 'tel:+123' }, { url: 'mailto:me@example.test', external: true }]) {
    await assert.rejects(handler.handle(params, {}), error => {
      assert.equal(error.toData().code, 'INVALID_ARGUMENT');
      assert.notEqual(error.originalCause?.name, 'LineBridgeError');
      return true;
    });
  }
  assert.equal(calls, 0);
  await assert.rejects(handler.handle({ url: 'https://liff.line.me/123' }, {}), error => {
    assert.equal(error.toData().code, 'INVALID_ARGUMENT');
    assert.equal(JSON.stringify(error.toData()).includes('private'), false); return true;
  });
});

test('handler disposal leaves the Binding-owned browser available for its owner', async () => {
  let documentId = 1, dismissed = 0, disposed = 0;
  const cleanups = [];
  const handler = createHandler(context({ getDocumentId: () => documentId,
    addCleanup: cleanup => cleanups.push(cleanup) }), presenter({
    dismissAll() { dismissed++; }, dispose() { disposed++; }
  }));
  await handler.handle({ url: 'https://example.test/a' }, {});
  await handler.handle({ url: 'https://example.test/b', external: true }, {});
  assert.equal(cleanups.length, 0);
  handler.dispose(); handler.dispose();
  assert.equal(dismissed, 0);
  assert.equal(disposed, 0);
  await assert.rejects(handler.handle({ url: 'https://example.test/d' }, {}), { code: 'SESSION_CLOSED' });
});

test('actual Bridge keeps concurrent host openings correlated and drops old-document completions', async () => {
  const vm = require('node:vm');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const pending = new Map(), events = [];
  const session = new MiniAppSession('open-source', {
    info: { appId: 'source', vendor: 'line', url: 'https://example.com/' },
    adapter: new LineAdapter({ mode: 'client' }), vendor: new LineVendor(), swipeBackController: { dispose() {} },
    onOpenMiniApp: app => new Promise(resolve => pending.set(app.appId, resolve))
  }, {});
  const host = applicationLifecycle(load);
  host.onAbilityCreate({ context: session.uiAbilityContext });
  host.onAbilityForeground({ context: session.uiAbilityContext });
  const window = { _liff: {}, liff: { _dispatchEvent(value) { events.push(JSON.parse(value)); } } };
  session.attach({ async evaluate(script) { vm.runInNewContext(script, { window }); return ''; } });
  session.beginDocument(session.initialUrl); session.finishDocument(session.initialUrl);
  const proxy = session.getBinding().injections[0].object;
  const open = (id, callback) => proxy.postMessage('openWindow', '', callback, JSON.stringify({ url: 'https://liff.line.me/' + id }));
  open('first', 'one'); open('second', 'two');
  pending.get('second')(); pending.get('first')();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(events.filter(event => event.type === 'openWindow').map(event => event.callbackId), ['two', 'one']);
  open('late', 'old'); session.beginDocument('https://example.com/new'); pending.get('late')();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(events.filter(event => event.type === 'openWindow').length, 2);
  assert.equal(session.appId, 'source'); session.close();
});
