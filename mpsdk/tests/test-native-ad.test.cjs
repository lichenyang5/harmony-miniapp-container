const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const check = 'VKWebAppCheckNativeAds', show = 'VKWebAppShowNativeAds';
async function flush() { for (let i = 0; i < 20; i++) await Promise.resolve(); }

function fixture(t, { debug = true, enabled = true, sharedLoad, sharedAdapter } = {}) {
  const load = sharedLoad || createLoader({}, {}, {}, {}, () => true, { DEBUG: debug });
  const { VkAdapter } = load('main/ets/vendors/vk/VkAdapter');
  const { VkVendor } = load('main/ets/vendors/vk/VkVendor');
  let controller, created = 0;
  const views = [], sent = [], cleanups = [];
  const context = { id: 'native-ad', appId: 'same-app', vendorId: 'vk', documentId: 1,
    uiAbilityContext: { applicationInfo: { accessTokenId: 1 } },
    getDocumentId() { return this.documentId; }, addCleanup(fn) { cleanups.push(fn); },
    async send(script) {
      new Function('window', script)({ atomicBridge: { postResponse(id, data) { sent.push({ id, data }); } } });
      return true;
    }
  };
  const adapter = sharedAdapter || new VkAdapter(enabled ? { createTestNativeAd: () => {
    created++;
    const { VkTestNativeAdController } = load('main/ets/vendors/vk/testing/VkTestNativeAdController');
    controller = new VkTestNativeAdController(view => views.push(view));
    return controller;
  } } : {});
  const binding = new VkVendor().createBinding(context, adapter);
  t.after(() => binding.dispose());
  return { views, sent, binding, controller: () => controller, created: () => created,
    request(method, params = { ad_format: 'interstitial' }, id = 'request') {
      return binding.injections[0].object.onInterceptRequest(JSON.stringify({ type: 'vk-connect', handler: method,
        params: { ...params, request_id: id } }), id);
    },
    navigate() { context.documentId++; cleanups.splice(0).forEach(fn => fn()); binding.onDocumentChanged(context.documentId); }
  };
}

test('native ads are untouched by default and in Release even with a test factory', async t => {
  for (const options of [{ enabled: false }, { debug: false }]) {
    const f = fixture(t, options);
    for (const method of [check, show]) assert.equal(f.request(method).intercept, false);
    await flush();
    assert.equal(f.created(), 0); assert.equal(f.sent.length, 0);
  }
});

test('local interstitial checks readiness and reports success only after nonzero layout', async t => {
  const f = fixture(t);
  assert.equal(f.request(check).intercept, true); await flush();
  assert.deepEqual(f.sent.pop().data, { type: check + 'Result', data: { result: true, request_id: 'request' } });
  f.request(show, { ad_format: 'interstitial' }, 'show'); await flush();
  assert.equal(f.sent.length, 0);
  const view = f.views.at(-1);
  assert.deepEqual(view, { id: 1 });
  f.controller().confirmShown(view.id, 0, 0); await flush();
  assert.equal(f.sent.length, 0);
  f.controller().confirmShown(view.id, 1080, 1600); await flush();
  assert.deepEqual(f.sent.pop().data, { type: show + 'Result', data: { result: true, request_id: 'show' } });
  f.request(check); await flush();
  assert.equal(f.sent.pop().data.data.result, false, 'occupied local material is unavailable for another show');
  const closing = f.controller().close();
  assert.equal(f.views.at(-1), undefined);
  assert.equal(f.controller().hasActiveAd(), true, 'still owns back presses until removal confirmation');
  f.controller().confirmHidden(view.id); await closing;
  f.request(check); await flush();
  assert.equal(f.sent.pop().data.data.result, true);
});

test('native test validates ad_format and use_waterfall without creating a view', async t => {
  const f = fixture(t);
  for (const method of [check, show]) {
    for (const [params, code] of [[{}, 2], [{ ad_format: null }, 5], [{ ad_format: 'video' }, 5],
      [{ ad_format: 'interstitial', use_waterfall: null }, 5], [{ ad_format: 'interstitial', use_waterfall: 'true' }, 5]]) {
      assert.equal(f.request(method, params).intercept, true); await flush();
      assert.equal(f.sent.pop().data.data.error_data.error_code, code);
      assert.equal(f.views.length, 0);
    }
  }
});

test('reward has no local inventory and never returns a fabricated reward success', async t => {
  const f = fixture(t);
  assert.equal(f.request(check, { ad_format: 'reward', use_waterfall: true }).intercept, true); await flush();
  assert.equal(f.sent.pop().data.data.result, false);
  f.request(show, { ad_format: 'reward' }); await flush();
  assert.equal(f.sent.pop().data.data.error_data.error_code, 6);
  assert.equal(f.views.length, 0);
});

test('duplicate interstitial requests cannot replace a pending or visible ad', async t => {
  const f = fixture(t);
  assert.equal(f.request(show).intercept, true);
  const view = f.views.at(-1);
  f.request(show); await flush();
  assert.equal(f.sent.pop().data.type, show + 'Failed');
  f.controller().confirmShown(view.id, 800, 1200); await flush(); f.sent.length = 0;
  f.request(show); await flush();
  assert.equal(f.sent.pop().data.type, show + 'Failed');
  assert.equal(f.views.length, 1);
});

test('back press closes only the active test interstitial and remains consumed until removal', async t => {
  const f = fixture(t);
  assert.equal(f.request(check).intercept, true);
  assert.equal(f.controller().handleBackPress(), false);
  f.request(show);
  const view = f.views.at(-1);
  f.controller().confirmShown(view.id, 800, 1200); await flush();
  assert.equal(f.controller().handleBackPress(), true);
  assert.equal(f.controller().handleBackPress(), true);
  assert.equal(f.views.at(-1), undefined);
  f.controller().confirmHidden(view.id); await flush();
  assert.equal(f.controller().handleBackPress(), false);
});

test('show timeout stays failed even if a late layout arrives', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const f = fixture(t);
  assert.equal(f.request(show).intercept, true);
  const view = f.views.at(-1);
  t.mock.timers.tick(3001); await flush();
  assert.equal(f.sent.pop().data.type, show + 'Failed');
  assert.equal(f.controller().hasActiveAd(), false, 'a view that never mounted needs no disappearance event');
  f.controller().confirmShown(view.id, 800, 1200); await flush();
  assert.equal(f.sent.length, 0);
  f.controller().confirmHidden(view.id);
  assert.equal(f.controller().hasActiveAd(), false);
});

test('document change and disposal clear the overlay and discard pending replies', async t => {
  for (const dispose of [false, true]) {
    const f = fixture(t);
    assert.equal(f.request(show).intercept, true);
    const old = f.views.at(-1);
    if (dispose) f.binding.dispose(); else f.navigate();
    f.controller().confirmShown(old.id, 800, 1200); await flush();
    assert.equal(f.sent.length, 0); assert.equal(f.views.at(-1), undefined);
    assert.equal(f.controller().handleBackPress(), false);
    if (!dispose) {
      f.request(show); const current = f.views.at(-1);
      f.controller().confirmHidden(old.id);
      f.controller().confirmShown(current.id, 800, 1200); await flush();
      assert.equal(f.sent.pop().data.data.result, true);
    }
  }
});

test('same app and shared adapter use independent native ad controllers', async t => {
  const load = createLoader({}, {}, {}, {}, () => true, { DEBUG: true });
  const { VkAdapter } = load('main/ets/vendors/vk/VkAdapter');
  const { VkTestNativeAdController } = load('main/ets/vendors/vk/testing/VkTestNativeAdController');
  const controllers = [], states = [];
  const adapter = new VkAdapter({ createTestNativeAd: () => {
    const index = controllers.length;
    const ad = new VkTestNativeAdController(state => { states[index] = state; });
    controllers.push(ad); return ad;
  } });
  const first = fixture(t, { sharedLoad: load, sharedAdapter: adapter });
  const second = fixture(t, { sharedLoad: load, sharedAdapter: adapter });
  first.request(show); second.request(show);
  controllers[0].confirmShown(states[0].id, 800, 1200);
  controllers[1].confirmShown(states[1].id, 900, 1600); await flush();
  first.binding.dispose();
  assert.equal(states[0], undefined);
  assert.equal(controllers[1].hasActiveAd(), true);
  second.request(show); await flush();
  assert.equal(second.sent.at(-1).data.type, show + 'Failed');
});

test('close failure retains ad occupancy and can be retried without leaking host error', async t => {
  const load = createLoader();
  const { VkTestNativeAdController } = load('main/ets/vendors/vk/testing/VkTestNativeAdController');
  let state, failRemoval = true;
  const controller = new VkTestNativeAdController(value => {
    if (!value && failRemoval) throw new Error('private');
    state = value;
  });
  t.after(() => controller.dispose());
  const showing = controller.show();
  const id = state.id;
  controller.confirmShown(id, 800, 1200); await showing;
  await assert.rejects(controller.close(), { code: 'SYSTEM_ERROR' });
  assert.equal(controller.hasActiveAd(), true);
  assert.equal(controller.check().result, false);
  failRemoval = false;
  const closing = controller.close();
  controller.confirmHidden(id); await closing;
  assert.equal(controller.check().result, true);
});

test('closing before layout cancels pending success and stale events cannot open a new ad', async t => {
  const f = fixture(t);
  f.request(show); const first = f.views.at(-1);
  const closing = f.controller().close();
  f.controller().confirmHidden(first.id); await closing; await flush();
  assert.equal(f.sent.pop().data.type, show + 'Failed');
  f.request(show); const second = f.views.at(-1);
  f.controller().confirmShown(first.id, 800, 1200); await flush();
  assert.equal(f.sent.length, 0);
  f.controller().confirmHidden(first.id);
  f.controller().confirmShown(second.id, 800, 1200); await flush();
  assert.equal(f.sent.pop().data.data.result, true);
});

test('closing before mount releases back handling without an onDisAppear callback', async t => {
  const f = fixture(t);
  f.request(show);
  assert.equal(f.controller().handleBackPress(), true);
  await flush();
  assert.equal(f.controller().hasActiveAd(), false);
  assert.equal(f.controller().handleBackPress(), false);
  assert.equal(f.sent.pop().data.type, show + 'Failed');
  f.request(check); await flush();
  assert.equal(f.sent.pop().data.data.result, true);
});

test('mounted-but-not-laid-out ad retains back ownership until disappearance', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const f = fixture(t);
  f.request(show); const view = f.views.at(-1);
  f.controller().confirmMounted(view.id);
  t.mock.timers.tick(3001); await flush();
  assert.equal(f.sent.pop().data.type, show + 'Failed');
  assert.equal(f.controller().hasActiveAd(), true);
  assert.equal(f.controller().check().result, false);
  f.controller().confirmHidden(view.id);
  assert.equal(f.controller().handleBackPress(), false);
  assert.equal(f.controller().check().result, true);
});
