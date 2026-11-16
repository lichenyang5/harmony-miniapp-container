const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

async function flush() { for (let i = 0; i < 20; i++) await Promise.resolve(); }

function fixture(t, { debug = true, enabled = true, adapter, load: sharedLoad } = {}) {
  const load = sharedLoad || createLoader({}, {}, {}, {}, () => true, { DEBUG: debug });
  const { VkAdapter } = load('main/ets/vendors/vk/VkAdapter');
  const { VkVendor } = load('main/ets/vendors/vk/VkVendor');
  const sent = [], cleanups = [], views = [];
  let controller, created = 0;
  const context = { id: 'banner-session', appId: 'same-app', vendorId: 'vk', documentId: 1,
    uiAbilityContext: { applicationInfo: { accessTokenId: 1 } },
    getDocumentId() { return this.documentId; }, addCleanup(fn) { cleanups.push(fn); },
    async send(script) {
      new Function('window', script)({ atomicBridge: { postResponse(id, data) { sent.push({ id, data }); } } });
      return true;
    }
  };
  const host = enabled ? { createTestBanner: () => {
    created++;
    const { VkTestBannerController } = load('main/ets/vendors/vk/testing/VkTestBannerController');
    controller = new VkTestBannerController(view => views.push(view));
    return controller;
  } } : {};
  const binding = new VkVendor().createBinding(context, adapter || new VkAdapter(host));
  t.after(() => binding.dispose());
  const proxy = binding.injections[0].object;
  return { load, context, binding, sent, views, created: () => created,
    controller: () => controller,
    request(method, params = {}, id = 'request') {
      return proxy.onInterceptRequest(JSON.stringify({ type: 'vk-connect', handler: method,
        params: { ...params, request_id: id } }), id);
    },
    navigate() {
      context.documentId++;
      cleanups.splice(0).forEach(fn => fn());
      binding.onDocumentChanged(context.documentId);
    }
  };
}

const methods = ['VKWebAppCheckBannerAd', 'VKWebAppShowBannerAd', 'VKWebAppHideBannerAd'];

test('default and release builds leave all three methods to VK without creating test UI', async t => {
  for (const options of [{ enabled: false }, { debug: false }]) {
    const f = fixture(t, options);
    for (const method of methods) assert.equal(f.request(method).intercept, false);
    await flush();
    assert.equal(f.created(), 0);
    assert.equal(f.sent.length, 0);
  }
});

test('opted-in debug banner completes check/show/check/hide/check through real proxy', async t => {
  const f = fixture(t);
  assert.equal(f.request(methods[0]).intercept, true);
  await flush();
  assert.deepEqual(f.sent.pop().data, { type: 'VKWebAppCheckBannerAdResult', data: { result: false, request_id: 'request' } });
  f.request(methods[1], {}, 'show');
  await flush();
  assert.equal(f.sent.length, 0, 'show must await actual layout');
  const view = f.views.at(-1);
  assert.deepEqual(view, { id: 1, location: 'bottom', layout: 'resize', canClose: true });
  f.controller().confirmLayout(view.id, 1080, 192);
  await flush();
  const expected = { result: true, banner_width: 1080, banner_height: 192, banner_location: 'bottom', layout_type: 'resize' };
  assert.deepEqual(f.sent.pop().data, { type: 'VKWebAppShowBannerAdResult', data: { ...expected, request_id: 'show' } });
  f.request(methods[0]); await flush();
  assert.deepEqual(f.sent.pop().data.data, { ...expected, request_id: 'request' });
  f.request(methods[2], {}, 'hide'); await flush();
  assert.equal(f.views.at(-1), undefined);
  assert.equal(f.sent.length, 0, 'hide must await removal from UI');
  f.controller().confirmHidden(view.id); await flush();
  assert.deepEqual(f.sent.pop().data, { type: 'VKWebAppHideBannerAdResult', data: { ...expected, request_id: 'hide' } });
  f.request(methods[0]); await flush();
  assert.equal(f.sent.pop().data.data.result, false);
  f.request(methods[2]); await flush();
  assert.equal(f.sent.pop().data.data.result, false);
});

test('strict invalid options return client 5 before mounting anything', async t => {
  const f = fixture(t);
  for (const params of [{ banner_location: null }, { banner_location: 'left' },
    { layout_type: null }, { layout_type: 'RESIZE' }, { can_close: null }, { can_close: 'false' }]) {
    assert.equal(f.request(methods[1], params).intercept, true);
    await flush();
    assert.equal(f.sent.pop().data.data.error_data.error_code, 5);
    assert.equal(f.views.length, 0);
  }
});

test('top normalizes to resize; bottom overlay preserves layout and can_close false', async t => {
  for (const [location, layout] of [['top', 'resize'], ['bottom', 'overlay']]) {
    const f = fixture(t);
    assert.equal(f.request(methods[1], { banner_location: location, layout_type: 'overlay', can_close: false }).intercept, true);
    const view = f.views.at(-1);
    assert.equal(view.layout, layout);
    assert.equal(view.canClose, false);
    f.controller().confirmLayout(view.id, 800, 160); await flush();
    assert.equal(f.sent.pop().data.data.layout_type, layout);
  }
});

test('double show rejects without replacing the current banner; dimensions track layout changes', async t => {
  const f = fixture(t);
  assert.equal(f.request(methods[1]).intercept, true);
  const view = f.views.at(-1);
  f.controller().confirmLayout(view.id, 1000, 160); await flush(); f.sent.length = 0;
  f.request(methods[1]); await flush();
  assert.equal(f.sent.pop().data.type, 'VKWebAppShowBannerAdFailed');
  assert.equal(f.views.length, 1);
  f.controller().confirmLayout(view.id, 1500, 200);
  f.request(methods[0]); await flush();
  assert.equal(f.sent.pop().data.data.banner_width, 1500);
});

test('page change clears UI and drops pending results, and a new document can show again', async t => {
  const f = fixture(t);
  assert.equal(f.request(methods[1]).intercept, true);
  const old = f.views.at(-1);
  f.navigate();
  f.controller().confirmLayout(old.id, 1000, 160); await flush();
  assert.equal(f.views.at(-1), undefined);
  assert.equal(f.sent.length, 0);
  f.request(methods[1]);
  const next = f.views.at(-1);
  assert.notEqual(next.id, old.id);
  f.controller().confirmHidden(old.id);
  f.controller().confirmLayout(next.id, 800, 120); await flush();
  assert.equal(f.sent.pop().data.data.result, true);
  f.navigate(); await flush();
  assert.equal(f.views.at(-1), undefined);
});

test('close cancels pending show and late host callbacks never produce a success', async t => {
  const f = fixture(t);
  assert.equal(f.request(methods[1]).intercept, true);
  const view = f.views.at(-1);
  f.binding.dispose();
  f.controller().confirmLayout(view.id, 1000, 100); await flush();
  assert.equal(f.views.at(-1), undefined);
  assert.equal(f.sent.length, 0);
});

test('native ads remain passthrough even with local banners enabled', t => {
  const f = fixture(t);
  for (const method of ['VKWebAppCheckNativeAds', 'VKWebAppShowNativeAds']) {
    assert.equal(f.request(method, { ad_format: 'interstitial' }).intercept, false);
  }
});

test('zero-size layout is not reported as a visible banner', async t => {
  const f = fixture(t);
  f.request(methods[1]);
  const view = f.views.at(-1);
  f.controller().confirmLayout(view.id, 1000, 100); await flush(); f.sent.length = 0;
  f.controller().confirmLayout(view.id, 0, 0);
  f.request(methods[0]); await flush();
  assert.equal(f.sent.pop().data.data.result, false);
});

test('no layout acknowledgement fails in bounded time without fabricating show success', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const f = fixture(t);
  f.request(methods[1]);
  t.mock.timers.tick(3001); await flush();
  assert.equal(f.sent.pop().data.type, 'VKWebAppShowBannerAdFailed');
  assert.equal(f.views.at(-1), undefined);
  f.request(methods[0]); await flush();
  assert.equal(f.sent.pop().data.data.result, false);
});

test('hide without removal confirmation fails instead of returning true', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const f = fixture(t);
  f.request(methods[1]);
  const view = f.views.at(-1);
  f.controller().confirmLayout(view.id, 1000, 100); await flush(); f.sent.length = 0;
  f.request(methods[2]);
  t.mock.timers.tick(3001); await flush();
  assert.equal(f.sent.pop().data.type, 'VKWebAppHideBannerAdFailed');
  assert.equal(f.controller().check().result, true, 'keep last confirmed state until disappearance');
  f.request(methods[1]); await flush();
  assert.equal(f.sent.pop().data.type, 'VKWebAppShowBannerAdFailed');
  f.request(methods[2]);
  f.controller().confirmHidden(view.id); await flush();
  assert.equal(f.sent.pop().data.data.result, true);
  assert.equal(f.controller().check().result, false);
});

test('user close respects can_close and completes after actual removal', async t => {
  for (const allowed of [false, true]) {
    const f = fixture(t);
    f.request(methods[1], { can_close: allowed });
    const view = f.views.at(-1);
    f.controller().confirmLayout(view.id, 1000, 100); await flush();
    const close = f.controller().closeByUser(view.id);
    if (allowed) {
      assert.equal(f.views.at(-1), undefined);
      f.controller().confirmHidden(view.id);
    }
    await close;
    assert.equal(f.controller().check().result, !allowed);
  }
});

test('two bindings sharing an adapter and app id cannot clear each others banner', async t => {
  const load = createLoader({}, {}, {}, {}, () => true, { DEBUG: true });
  const { VkAdapter } = load('main/ets/vendors/vk/VkAdapter');
  const { VkTestBannerController } = load('main/ets/vendors/vk/testing/VkTestBannerController');
  const controllers = [], views = [];
  const adapter = new VkAdapter({ createTestBanner: () => {
    const index = controllers.length;
    const controller = new VkTestBannerController(view => { views[index] = view; });
    controllers.push(controller);
    return controller;
  } });
  const first = fixture(t, { adapter, load }), second = fixture(t, { adapter, load });
  first.request(methods[1]); second.request(methods[1]);
  controllers[0].confirmLayout(views[0].id, 800, 100);
  controllers[1].confirmLayout(views[1].id, 900, 150); await flush();
  first.binding.dispose();
  assert.equal(views[0], undefined);
  second.request(methods[0]); await flush();
  assert.equal(second.sent.at(-1).data.data.banner_width, 900);
  assert.equal(second.sent.at(-1).data.data.result, true);
});

test('hide during pending show cancels show and never mistakes it for a displayed banner', async t => {
  const f = fixture(t);
  f.request(methods[1]);
  const view = f.views.at(-1);
  f.request(methods[2]);
  f.controller().confirmLayout(view.id, 1000, 160);
  f.controller().confirmHidden(view.id); await flush();
  assert.deepEqual(f.sent.map(item => item.data.type).sort(), ['VKWebAppHideBannerAdResult', 'VKWebAppShowBannerAdFailed']);
  assert.equal(f.sent.find(item => item.data.type === 'VKWebAppHideBannerAdResult').data.data.result, false);
});

test('host removal failure preserves visible state and allows a later hide retry', async t => {
  const load = createLoader();
  const { VkTestBannerController } = load('main/ets/vendors/vk/testing/VkTestBannerController');
  let view, failRemoval = true;
  const controller = new VkTestBannerController(state => {
    if (!state && failRemoval) throw new Error('private host exception');
    view = state;
  });
  t.after(() => controller.dispose());
  const showing = controller.show('bottom', 'resize', true);
  controller.confirmLayout(view.id, 1000, 160); await showing;
  await assert.rejects(controller.hide(), { code: 'SYSTEM_ERROR' });
  assert.equal(controller.check().result, true);
  assert.throws(() => controller.show('bottom', 'resize', true), { code: 'CAPABILITY_BUSY' });
  failRemoval = false;
  const id = view.id;
  const hiding = controller.hide();
  controller.confirmHidden(id);
  assert.equal((await hiding).result, true);
  assert.equal(controller.check().result, false);
});
