const { applicationLifecycle } = require('./application-lifecycle.cjs');
﻿const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function fixture() {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } } });
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const binding = { injections: [], scripts: [], onDocumentChanged() {}, dispose() {},
    onLifecycleChanged(change) { this.foreground = change.current === 'FOREGROUND'; } };
  let resolve;
  const opened = [];
  const session = new MiniAppSession('live', {
    info: { appId: 'app', vendor: 'line', url: 'https://liff.line.me/app' },
    vendor: { vendorId: 'line', createBinding: () => binding }, adapter: {},
    swipeBackController: { dispose() {} },
    onOpenMiniApp(app) { opened.push(app); return new Promise(done => { resolve = done; }); }
  }, {});
  const host = applicationLifecycle(load);
  host.onAbilityCreate({ context: session.uiAbilityContext });
  host.onAbilityForeground({ context: session.uiAbilityContext });
  let paused = 0;
  session.attach({ evaluate: async () => '', pauseAllMedia() { paused++; } });
  session.beginDocument('https://app.example/');
  return { load, session, binding, opened, resolve: () => resolve(), paused: () => paused };
}

test('hidden sessions keep their document but pause media and reject new mini app opens', async () => {
  const f = fixture(); const id = f.session.getDocumentId();
  const target = { vendor: 'line', appId: 'target', url: 'https://liff.line.me/target' };
  const accepted = f.session.requestOpenMiniApp(target);
  applicationLifecycle(f.load).onAbilityBackground({ context: f.session.uiAbilityContext });
  assert.equal(f.paused(), 1);
  assert.equal(f.session.getDocumentId(), id);
  assert.equal(f.binding.foreground, false);
  await assert.rejects(f.session.requestOpenMiniApp(target), error => error.code === 'NOT_SUPPORTED');
  assert.equal(f.opened.length, 1);
  f.resolve(); await accepted;
  applicationLifecycle(f.load).onAbilityForeground({ context: f.session.uiAbilityContext }); assert.equal(f.session.lifecycle.isForeground(), true);
  f.session.close(); assert.equal(f.session.lifecycle.isForeground(), false);
});

test('navigation validates the URL and forwards it through the existing endpoint', async () => {
  const f = fixture();
  const { MiniAppNavigationController } = f.load('main/ets/web/MiniAppNavigationController');
  const navigation = new MiniAppNavigationController();
  const address = 'https://liff.line.me/app?liff.state=%2Fnext';
  await assert.rejects(navigation.navigateTo(address), error => error.code === 'WEB_NOT_ATTACHED');
  const calls = [];
  const endpoint = { session: f.session, navigateTo: async value => calls.push(value) };
  navigation.attach(endpoint);
  for (const url of ['javascript:alert(1)', 'data:text/html,x', 'file:///x', 'https://user:pass@example.com/', 'https://example.com/\n']) {
    await assert.rejects(navigation.navigateTo(url), error => error.code === 'INVALID_ARGUMENT');
  }
  await navigation.navigateTo(address); await navigation.navigateTo(address);
  assert.deepEqual(calls, [address, address]);
  assert.equal(navigation.endpoint, endpoint);
  f.session.close();
});
