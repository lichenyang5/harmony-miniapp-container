const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const tick = () => new Promise(resolve => setImmediate(resolve));
class PlatformURL extends URL { get params() { return this.searchParams; } }
function fixture(child = false, mode = 'client') {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const loads = [], requests = [];
  const account = { getVersion: () => 1, requireAccessToken: () => 'native',
    addInvalidationListener() {}, removeInvalidationListener() {},
    sendAccountRpc: async request => { requests.push(request);
      const method = request.method, value = 'https://shop.example/callback?state=a%2Bb#original';
      return Uint8Array.from([0x82, 0x41, 1, method.length, ...Buffer.from(method),
        0x0c, 0, 0x18, value.length, ...Buffer.from(value), 0, 0]); } };
  const launch = child ? { liffId: 'child-app', msit: 'original-ticket', verifier: 'parent-verifier',
    result: { url: 'https://child.example', featureToken: 'feature' }, onClose() {} } : undefined;
  const session = new MiniAppSession('web-login-binding', {
    info: { appId: child ? 'child-app' : 'app', vendor: 'line', url: 'https://liff.line.me/app' },
    adapter: new LineAdapter({ mode, account }), vendor: new LineVendor(launch), swipeBackController: { dispose() {} }
  }, {});
  session.attach({ evaluate: async () => '', pauseAllMedia() {}, load: (...args) => loads.push(args) });
  session.lifecycle.setHostForeground(true); session.beginDocument('https://shop.example/start');
  if (!child && mode === 'client') {
    session.interceptWebScheme({ url: 'liff://app/app?feature_token=feature', isMainFrame: true,
      documentId: session.getDocumentId() });
  }
  return { session, loads, requests, launch };
}
test('LIFF main and child OAuth return to the same endpoint with independent MST state', async () => {
  for (const child of [false, true]) {
    const f = fixture(child);
    const matched = f.session.interceptWebScheme({ url: 'https://access.line.me/oauth2/v2.1/login?x=1',
      isMainFrame: true, documentId: f.session.getDocumentId() });
    assert.equal(matched, true); await tick();
    assert.equal(f.requests.length, 1); assert.equal(f.loads.length, 1);
    const [request, scripts] = f.loads[0]; const target = new URL(request.url);
    const pair = f.session.getBinding().getModalSessionToken();
    assert.equal(target.searchParams.get(child ? 'mst_verifier' : 'mst_challenge'), child ? pair.verifier : pair.challenge);
    assert.equal(target.searchParams.get('msit'), child ? '' : null);
    assert.equal(request.headers, undefined);
    assert.match(request.url, /state=a%2Bb/); assert.equal(target.hash, '#original');
    assert.ok(scripts.some(script => script.script.includes(pair.challenge)));
    if (child) assert.equal(f.launch.verifier, 'parent-verifier');
    f.session.close();
  }
});
test('WEB binding never registers native OAuth handling even when a native account exists', () => {
  const f = fixture(false, 'web');
  assert.equal(f.session.interceptWebScheme({ url: 'https://access.line.me/oauth2/v2.1/login',
    isMainFrame: true, documentId: 1 }), false);
  assert.equal(f.requests.length, 0); f.session.close();
});

test('a browser owned by a background native container cannot start account OAuth', async () => {
  const f = fixture();
  const handlers = f.session.getBinding().createWebSchemeHandlers();
  const handler = handlers.find(handler => handler.id === 'line.webLogin');
  f.session.lifecycle.setHostForeground(false);
  assert.equal(handler.handle({ url: 'https://access.line.me/oauth2/v2.1/login', isMainFrame: true },
    { proceed: () => 42 }), 42);
  assert.equal(f.requests.length, 0);
  handlers.forEach(handler => handler.dispose?.()); f.session.close();
});

test('an obsolete load failure cannot roll back the MST state of a newer document', async () => {
  const f = fixture(); const pending = [];
  f.session.load = () => new Promise((resolve, reject) => pending.push({ resolve, reject }));
  const binding = f.session.getBinding();
  const first = binding.document.prepare('https://shop.example/first', true, 1).load();
  const failed = assert.rejects(first);
  f.session.beginDocument('https://shop.example/other');
  const second = binding.document.prepare('https://shop.example/second', true, 2).load();
  const latest = binding.getModalSessionToken();
  pending[0].reject(new Error('old load cancelled')); await failed;
  assert.deepEqual(binding.getModalSessionToken(), latest);
  assert.ok(binding.scripts.some(script => script.script.includes(latest.challenge)));
  pending[1].resolve(); await second;
  assert.deepEqual(binding.getModalSessionToken(), latest);
  f.session.close();
});
