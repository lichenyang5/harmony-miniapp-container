const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { applicationLifecycle } = require('./application-lifecycle.cjs');
class PlatformURL extends URL { get params() { return this.searchParams; } }
const loader = () => createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
  { '@kit.ArkTS': { url: { URL: PlatformURL } } });
const tick = () => new Promise(resolve => setImmediate(resolve));

function fixture() {
  const load = loader();
  const { LineLiffLinkSchemeHandler } = load('main/ets/vendors/line/scheme/LineLiffLinkSchemeHandler');
  const { WebSchemeDispatcher } = load('main/ets/web/scheme/WebSchemeDispatcher');
  const { WebSchemeDecision } = load('main/ets/web/scheme/WebSchemeTypes');
  const state = { current: 1, foreground: true, finished: true, allowed: true, liffId: 'source' };
  const opened = [], pending = [];
  const session = { id: 'direct', appId: 'source', isClosed: () => false, getDocumentId: () => state.current,
    getAdapter: () => ({ getLiffId: () => state.liffId }),
    lifecycle: { isForeground: () => state.foreground }, isDocumentFinished: () => state.finished,
    requestOpenMiniApp: app => {
      opened.push(app); return new Promise((resolve, reject) => pending.push({ resolve, reject }));
    }
  };
  const handler = new LineLiffLinkSchemeHandler({ session, canTransition: () => state.allowed });
  const dispatcher = new WebSchemeDispatcher([handler]);
  return { state, opened, pending, dispatcher, handler, WebSchemeDecision,
    navigate: (url, isMainFrame = true, documentId = state.current) => dispatcher.dispatch({ url, isMainFrame, documentId }) };
}

test('direct LIFF HTTPS navigation uses the shared dispatcher and preserves domain and state bytes', () => {
  for (const host of ['liff.line.me', 'miniapp.line.me']) {
    const f = fixture();
    assert.equal(f.navigate(`https://${host}/target/a%2Fb?x=%252F&x=2#frag`), f.WebSchemeDecision.CONSUME);
    assert.deepEqual(f.opened, [{ appId: 'target', vendor: 'line',
      url: `https://${host}/target?liff.state=${encodeURIComponent('/a%2Fb?x=%252F&x=2#frag')}` }]);
    f.dispatcher.dispose();
  }
});

test('ordinary links pass and same-app startup redirects pass until the document has finished', () => {
  const f = fixture(), { PASS, CONSUME, BLOCK } = f.WebSchemeDecision;
  for (const address of ['https://example.test/', 'http://example.test/target', 'https://liff.line.me/',
    'https://liff.line.me.evil.test/target']) assert.equal(f.navigate(address), PASS);
  f.state.finished = false;
  assert.equal(f.navigate('https://liff.line.me/source?x=1'), PASS);
  assert.equal(f.opened.length, 0);
  f.state.finished = true;
  assert.equal(f.navigate('https://liff.line.me/source?x=1'), CONSUME);
  assert.equal(f.navigate('https://liff.line.me/target'), BLOCK);
  assert.equal(f.navigate('http://liff.line.me/target'), BLOCK);
  f.dispatcher.dispose();
});

test('canonical self-links pass during startup and retain the parsed target ID when forwarded', () => {
  const f = fixture();
  f.state.liffId = '2007326019-vAg8J6Bp';
  f.state.finished = false;
  const target = 'https://miniapp.line.me/2007326019-vAg8J6Bp';
  assert.equal(f.navigate(target), f.WebSchemeDecision.PASS);
  assert.equal(f.opened.length, 0);
  f.state.finished = true;
  assert.equal(f.navigate(target), f.WebSchemeDecision.CONSUME);
  assert.deepEqual(f.opened, [{ appId: '2007326019-vAg8J6Bp', vendor: 'line', url: target }]);
  f.dispatcher.dispose();
});

test('view policy, frame, foreground, malformed target and document validity are enforced', () => {
  const f = fixture(), { PASS, BLOCK } = f.WebSchemeDecision;
  f.state.allowed = false; assert.equal(f.navigate('https://liff.line.me/target'), PASS);
  f.state.allowed = true;
  assert.equal(f.navigate('https://liff.line.me/target', false), BLOCK);
  f.state.foreground = false; assert.equal(f.navigate('https://liff.line.me/target'), BLOCK);
  f.state.foreground = true; assert.equal(f.navigate('https://liff.line.me/target', true, 99), BLOCK);
  for (const address of ['https://liff.line.me/%broken', 'https://liff.line.me:444/target',
    'https://liff.line.me/target\n']) assert.equal(f.navigate(address), BLOCK);
  assert.equal(f.opened.length, 0); f.dispatcher.dispose();
});

test('host rejection permits retry and old completion cannot clear a new document pending request', async () => {
  const f = fixture(), { CONSUME, BLOCK } = f.WebSchemeDecision;
  assert.equal(f.navigate('https://liff.line.me/target'), CONSUME);
  f.pending[0].reject(Error('host rejection')); await tick();
  assert.equal(f.navigate('https://liff.line.me/target'), CONSUME);
  f.dispatcher.reset(); f.state.current++;
  assert.equal(f.navigate('https://liff.line.me/other'), CONSUME);
  f.pending[1].resolve(); await tick();
  assert.equal(f.navigate('https://liff.line.me/third'), BLOCK);
  f.pending[2].resolve(); await tick();
  f.dispatcher.dispose(); assert.equal(f.navigate('https://liff.line.me/target'), BLOCK);
  assert.equal(f.opened.length, 3);
});

function string(value) { const b = Buffer.from(value); return [b.length, ...b]; }
function response(viewType) {
  return Uint8Array.from([0x82, 0x41, 1, ...string('issueLiffView'), 0x0c, 0,
    0x1c, ...(viewType === undefined ? [0x28] : [0x18, ...string(viewType), 0x18]),
    ...string('https://app.example/'), 0,
    0x18, ...string('context'), 0x18, ...string('access'), 0x18, ...string('feature'), 0, 0]);
}

test('native Binding reads issued view type and forwards only eligible direct links through its Session', async () => {
  for (const type of ['full', undefined, 'tall', 'compact', 'frame', 'unknown', '']) {
    const load = loader();
    const { MiniAppSession } = load('main/ets/core/Runtime');
    const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
    const { LineVendor } = load('main/ets/vendors/line/LineVendor');
    const opened = [];
    const account = { restoreSession: async () => true, getVersion: () => 1,
      addInvalidationListener() {}, removeInvalidationListener() {}, sendLiffRpc: async () => response(type) };
    const session = new MiniAppSession('direct-binding', {
      info: { vendor: 'line', appId: 'source', url: 'https://liff.line.me/source' },
      adapter: new LineAdapter({ mode: 'client', account }), vendor: new LineVendor(), swipeBackController: { dispose() {} },
      onOpenMiniApp: async app => { opened.push(app); }
    }, {});
    const host = applicationLifecycle(load);
    host.onAbilityCreate({ context: session.uiAbilityContext }); host.onAbilityForeground({ context: session.uiAbilityContext });
    session.attach({ evaluate: async () => '', pauseAllMedia() {} });
    try {
      await session.getBinding().prepareInitialLoad();
      session.beginDocument('https://app.example/'); session.finishDocument('https://app.example/');
      const handled = session.interceptWebScheme({ url: 'https://miniapp.line.me/target?x=1',
        isMainFrame: true, documentId: session.getDocumentId() });
      const eligible = type === 'full' || type === undefined;
      assert.equal(handled, eligible, String(type)); await tick();
      assert.equal(opened.length, eligible ? 1 : 0, String(type));
    } finally { session.close(); }
  }
});

test('WEB mode does not register a native HTTPS transition handler', () => {
  const load = loader();
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const session = new MiniAppSession('web-direct', {
    info: { vendor: 'line', appId: 'source', url: 'https://liff.line.me/source' },
    adapter: new LineAdapter({ mode: 'web' }), vendor: new LineVendor(), swipeBackController: { dispose() {} }
  }, {});
  session.attach({ evaluate: async () => '', pauseAllMedia() {} });
  assert.equal(session.interceptWebScheme({ url: 'https://liff.line.me/target', isMainFrame: true, documentId: 0 }), false);
  session.close();
});


test('HTTP LIFF direct navigation upgrades to HTTPS before forwarding; ordinary HTTP remains untouched', () => {
  const f = fixture();
  assert.equal(f.navigate('http://example.test/'), f.WebSchemeDecision.PASS);
  assert.equal(f.navigate('http://miniapp.line.me/target/path?x=1'), f.WebSchemeDecision.CONSUME);
  assert.equal(f.opened[0].url, 'https://miniapp.line.me/target?liff.state=%2Fpath%3Fx%3D1');
  f.dispatcher.dispose();
});

test('a child view uses its own Session transfer even when its modal presentation is compact', async () => {
  const load = loader();
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const opened = [];
  const launch = { liffId: 'child', msit: 'ticket', verifier: 'verifier', onClose() {},
    result: { url: 'https://child.example/', viewType: 'compact', accessToken: 'child-access', featureToken: 'child-feature' } };
  const session = new MiniAppSession('child-direct', {
    info: { vendor: 'line', appId: 'child', url: launch.result.url },
    adapter: new LineAdapter({ mode: 'client' }), vendor: new LineVendor(launch), swipeBackController: { dispose() {} },
    onOpenMiniApp: async app => { opened.push(app); }
  }, {});
  const host = applicationLifecycle(load);
  host.onAbilityCreate({ context: session.uiAbilityContext }); host.onAbilityForeground({ context: session.uiAbilityContext });
  session.attach({ evaluate: async () => '', pauseAllMedia() {} });
  try {
    session.beginDocument(launch.result.url); session.finishDocument(launch.result.url);
    assert.equal(session.interceptWebScheme({ url: 'https://liff.line.me/target', isMainFrame: true,
      documentId: session.getDocumentId() }), true);
    await tick();
    assert.deepEqual(opened.map(({ appId, vendor, url }) => ({ appId, vendor, url })),
      [{ appId: 'target', vendor: 'line', url: 'https://liff.line.me/target' }]);
    assert.equal(opened[0].customUserAgent, undefined);
  } finally { session.close(); }
});
