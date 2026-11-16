const { applicationLifecycle } = require('./application-lifecycle.cjs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

class PlatformURL extends URL {
  get params() { return this.searchParams; }
}

function fixture(customBinding) {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const line = new LineVendor();
  const vendor = customBinding ? { vendorId: 'test', createBinding: () => customBinding } : line;
  const session = new MiniAppSession('navigation-test', {
    info: { appId: 'target-app', vendor: vendor.vendorId, url: 'https://example.com/' },
    vendor, adapter: new LineAdapter({ mode: 'client' }), swipeBackController: { dispose() {} }
  }, {});
  const scripts = [];
  const host = applicationLifecycle(load);
  host.onAbilityCreate({ context: session.uiAbilityContext });
  host.onAbilityForeground({ context: session.uiAbilityContext });
  session.attach({ evaluate(script) { scripts.push(script); return Promise.resolve(''); } });
  session.beginDocument('https://example.com/');
  const binding = session.getBinding();
  const navigate = (url, isMainFrame = true, documentId = session.getDocumentId()) =>
    session.interceptWebScheme({ url, isMainFrame, documentId });
  return { session, binding, navigate, scripts };
}

test('navigation default passes through; stale, closed and throwing handlers are contained', () => {
  const { WebSchemeDecision } = createLoader()('main/ets/web/scheme/WebSchemeTypes');
  const binding = { onDocumentChanged() {}, dispose() {} };
  const f = fixture(binding);
  assert.equal(f.navigate('https://example.com/next'), false);
  let received;
  let throwing = false;
  let factories = 0;
  const registered = fixture({ ...binding, createWebSchemeHandlers() {
    factories++;
    return [{ id: 'custom', supports: request => /^custom:/i.test(request.url), handle(request) {
      if (throwing) throw new Error('private URL/token');
      received = request; return WebSchemeDecision.CONSUME;
    } }];
  } });
  assert.equal(registered.navigate('custom://command'), true);
  assert.equal(received.documentId, registered.session.getDocumentId());
  received = undefined;
  assert.equal(registered.navigate('custom://command', true, 0), true);
  assert.equal(received, undefined);
  throwing = true;
  assert.equal(registered.navigate('custom://command'), true);
  registered.session.beginDocument('https://example.com/next');
  assert.equal(factories, 1);
  registered.session.close();
  assert.equal(registered.navigate('custom://command'), true);
});

test('LINE normalizes scheme case while preserving exact command and authority boundaries', () => {
  const f = fixture();
  for (const address of ['liff://APP/target-app?feature_token=t',
    'liff://application/target-app?feature_token=t', 'liff://user@app/target-app?feature_token=t',
    'liff://app:123/target-app?feature_token=t', 'liff://app.example/target-app?feature_token=t',
    'liff:app/target-app?feature_token=t']) {
    assert.equal(f.navigate(address), false, address);
    assert.equal(f.binding.getAppState(), undefined);
  }
  assert.equal(f.navigate('LiFf://app/target-app?feature_token=normalized'), true);
  assert.equal(f.binding.getAppState().featureToken, 'normalized');
});

test('LINE stores the decoded first app command once without navigation or success callbacks', () => {
  const f = fixture();
  for (const url of ['https://example.com/', 'line://picker', 'liff://application/x']) {
    assert.equal(f.navigate(url), false);
  }
  assert.equal(f.binding.getAppState(), undefined);
  assert.equal(f.navigate('liff://app/target-app/extra?feature_token=a%2Bb%26c'), true);
  assert.deepEqual(f.binding.getAppState(), { liffId: 'target-app', featureToken: 'a+b&c', lineMode: 'client' });
  const proxy = f.binding.injections[0].object;
  assert.deepEqual(proxy.getAppState(), f.binding.getAppState());
  assert.equal(f.binding.injections[0].methods.includes('getAppState'), false);
  const snapshot = f.binding.getAppState(); snapshot.featureToken = 'changed';
  assert.equal(f.binding.getAppState().featureToken, 'a+b&c');
  f.navigate('liff://app/target-app?feature_token=second');
  f.navigate('liff://app/another-app?feature_token=other');
  assert.equal(f.binding.getAppState().featureToken, 'a+b&c');
  assert.equal(f.scripts.length, 0);
});

test('invalid, subframe and stale app commands cannot establish LINE state', () => {
  const f = fixture();
  for (const url of ['liff://app', 'liff://app/?feature_token=t',
    'liff://app/target-app', 'liff://app/target-app?feature_token=',
    'liff://app/another-app?feature_token=t', 'liff://app/%ZZ?feature_token=t']) {
    assert.equal(f.navigate(url), true);
    assert.equal(f.binding.getAppState(), undefined);
  }
  const command = 'liff://app/target-app?feature_token=t';
  assert.equal(f.navigate(command, false), true);
  assert.equal(f.navigate(command, true, 0), true);
  assert.equal(f.binding.getAppState(), undefined);
  f.navigate('liff://app/target-app?feature_token=%20');
  assert.equal(f.binding.getAppState().featureToken, ' '); // No implicit trim.
});

test('LINE state survives refresh, is isolated across same-app sessions and clears on close', () => {
  const a = fixture(); const b = fixture();
  const proxy = a.binding.injections[0].object;
  a.navigate('liff://app/target-app?feature_token=first');
  b.navigate('liff://app/target-app?feature_token=second');
  a.session.beginDocument('https://example.com/');
  assert.equal(a.binding.getAppState().featureToken, 'first');
  a.session.close();
  assert.equal(a.binding.getAppState(), undefined);
  assert.equal(proxy.getAppState(), undefined);
  assert.equal(b.binding.getAppState().featureToken, 'second');
  assert.equal(a.navigate('liff://app/target-app?feature_token=late'), true);
  assert.equal(a.binding.getAppState(), undefined);
});
