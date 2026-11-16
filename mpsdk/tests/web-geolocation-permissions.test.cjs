const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { applicationLifecycle } = require('./application-lifecycle.cjs');
const APPROX = 'ohos.permission.APPROXIMATELY_LOCATION', PRECISE = 'ohos.permission.LOCATION';
const flush = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };

function fixture(load = createLoader(), vendor) {
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { VkVendor } = load('main/ets/vendors/vk/VkVendor');
  const { VkAdapter } = load('main/ets/vendors/vk/VkAdapter');
  const { SessionWebGeolocationPermissions } = load('main/ets/web/SessionWebGeolocationPermissions');
  const session = new MiniAppSession('geo-session', {
    info: { appId: 'same-app', vendor: 'vk', url: 'https://vk.ru/app123' },
    vendor: vendor ?? new VkVendor(), adapter: new VkAdapter(),
    swipeBackController: { setEnabled() {}, dispose() {} }
  }, { applicationInfo: { accessTokenId: 1 } });
  const host = applicationLifecycle(load);
  host.onAbilityCreate({ context: session.uiAbilityContext });
  host.onAbilityForeground({ context: session.uiAbilityContext });
  session.attach({ evaluate: async () => '', pauseAllMedia() {} });
  const pending = []; let foreground = true;
  const geo = new SessionWebGeolocationPermissions(session, {
    assertForeground() { if (!foreground) throw Error('background'); },
    request(isCurrent) { return new Promise((resolve, reject) => pending.push({ isCurrent, resolve, reject })); }
  });
  const navigate = url => { session.beginDocument(url); geo.beginDocument(url); };
  navigate(session.initialUrl);
  return { session, geo, pending, navigate, background() { foreground = false; } };
}

function request(origin = 'https://vk.ru') {
  const results = [];
  return { origin, results, finish: allow => results.push(allow) };
}

test('geolocation adapter uses the original origin and never persists site authorization', () => {
  const { ArkWebGeolocationRequest } = createLoader()('main/ets/web/ArkWebGeolocationRequest');
  const results = [];
  const r = new ArkWebGeolocationRequest('https://vk.ru', { invoke: (...args) => results.push(args) });
  assert.equal(r.origin, 'https://vk.ru'); r.finish(true); r.finish(false);
  assert.deepEqual(results, [['https://vk.ru', true, false], ['https://vk.ru', false, false]]);
});

test('geolocation grants, denial and native errors settle the original request once', async () => {
  for (const outcome of [true, false, 'error']) {
    const f = fixture(), r = request(); f.geo.handle(r); f.geo.handle(r);
    assert.equal(f.pending.length, 1); assert.deepEqual(r.results, []);
    if (outcome === 'error') f.pending[0].reject(Error('native failure'));
    else f.pending[0].resolve(outcome);
    await flush(); assert.deepEqual(r.results, [outcome === true]);
    f.geo.dispose(); f.session.close(); assert.equal(r.results.length, 1);
  }
});

test('geolocation rejects missing vendor policy and background before prompting', () => {
  for (const mode of ['vendor', 'background']) {
    const vendor = mode === 'vendor' ? { vendorId: 'other', createBinding: () => ({
      scripts: [], injections: [], onDocumentChanged() {}, dispose() {}
    }) } : undefined;
    const f = fixture(createLoader(), vendor), r = request();
    if (mode === 'background') f.background();
    f.geo.handle(r); assert.deepEqual(r.results, [false]); assert.equal(f.pending.length, 0);
    f.geo.dispose(); f.session.close();
  }
});

test('non-VK geolocation origins and top documents use the system permission result', async () => {
  for (const address of ['https://vk.ru', 'https://miniapp.example']) {
    for (const allowed of [true, false]) {
      const f = fixture(), r = request('https://frame.example');
      try {
        f.navigate(address); f.geo.handle(r);
        assert.equal(f.pending.length, 1); assert.deepEqual(r.results, []);
        f.pending[0].resolve(allowed); await flush();
        assert.deepEqual(r.results, [allowed]);
      } finally { f.geo.dispose(); f.session.close(); }
    }
  }
});

test('navigation, session close, cancellation, disposal and background discard late geolocation grants', async () => {
  for (const mode of ['navigation', 'close', 'cancel', 'dispose', 'background']) {
    const f = fixture(), r = request(); f.geo.handle(r);
    if (mode === 'navigation') f.session.beginDocument('https://vk.ru/feed');
    if (mode === 'close') f.session.close();
    if (mode === 'cancel') f.geo.cancel();
    if (mode === 'dispose') { f.geo.dispose(); f.geo.dispose(); }
    if (mode === 'background') f.background();
    assert.equal(f.pending[0].isCurrent(), false);
    f.pending[0].resolve(true); await flush(); assert.deepEqual(r.results, [false]);
    if (mode === 'cancel' || mode === 'navigation') {
      if (mode === 'navigation') f.geo.beginDocument('https://vk.ru/feed');
      const next = request(); f.geo.handle(next); f.pending[1].resolve(true); await flush();
      assert.deepEqual(next.results, [true]);
    }
    if (mode === 'close' || mode === 'dispose') {
      f.geo.beginDocument('https://vk.ru'); const late = request(); f.geo.handle(late);
      assert.deepEqual(late.results, [false]);
    }
    f.geo.dispose(); f.session.close();
  }
});

test('same-app geolocation sessions and failing callbacks cannot interfere with each other', async () => {
  const load = createLoader(), first = fixture(load), second = fixture(load), a = request(), b = request();
  first.geo.handle({ origin: 'https://vk.ru', finish() { throw Error('detached'); } });
  first.geo.handle(a); second.geo.handle(b);
  assert.doesNotThrow(() => first.session.close());
  assert.deepEqual(a.results, [false]);
  second.pending[0].resolve(true); await flush(); assert.deepEqual(b.results, [true]);
  first.geo.dispose(); second.geo.dispose(); second.session.close();
});

test('native geolocation requires precise and approximate grants and requests an upgrade for approximate-only access', async () => {
  const load = createLoader();
  const { HarmonyGeolocationPermissionGateway } = load('main/ets/capabilities/permissions/HarmonyGeolocationPermissionGateway');
  const context = {}, lifecycle = applicationLifecycle(load);
  lifecycle.onAbilityCreate({ context }); lifecycle.onAbilityForeground({ context });
  for (const granted of [[APPROX, PRECISE], [APPROX], [], [PRECISE]]) {
    const prompts = [];
    const gateway = new HarmonyGeolocationPermissionGateway(context, {
      has: () => false, request: async permissions => { prompts.push(permissions); return granted; }
    });
    assert.equal(await gateway.request(() => true), granted.includes(APPROX) && granted.includes(PRECISE));
    assert.deepEqual(prompts, [[APPROX, PRECISE]]);
  }
  for (const granted of [[APPROX, PRECISE], [APPROX], [], [PRECISE]]) {
    const prompts = [];
    const upgrade = new HarmonyGeolocationPermissionGateway(context, {
      has: permission => permission === APPROX,
      request: async permissions => { prompts.push(permissions); return granted; }
    });
    assert.equal(await upgrade.request(() => true), granted.includes(APPROX) && granted.includes(PRECISE));
    assert.deepEqual(prompts, [[APPROX, PRECISE]]);
  }
  const existing = new HarmonyGeolocationPermissionGateway(context, {
    has: () => true, request() { throw Error('already fully authorized'); }
  });
  assert.equal(await existing.request(() => true), true);
});

test('geolocation and media share the same-host system prompt queue and skip canceled queued requests', async () => {
  const load = createLoader();
  const { HarmonyGeolocationPermissionGateway } = load('main/ets/capabilities/permissions/HarmonyGeolocationPermissionGateway');
  const { HarmonyMediaPermissionGateway } = load('main/ets/capabilities/media/HarmonyMediaPermissionGateway');
  const context = {}, lifecycle = applicationLifecycle(load), prompts = [], pending = [];
  lifecycle.onAbilityCreate({ context }); lifecycle.onAbilityForeground({ context });
  const access = { has: () => false, request: permissions => {
    prompts.push(permissions); return new Promise(resolve => pending.push(resolve));
  } };
  const media = new HarmonyMediaPermissionGateway(context, access);
  const geo = new HarmonyGeolocationPermissionGateway(context, access);
  const a = media.request(['TYPE_AUDIO_CAPTURE'], () => true);
  let current = true;
  const canceled = geo.request(() => current), b = geo.request(() => true);
  await flush(); assert.deepEqual(prompts, [['ohos.permission.MICROPHONE']]);
  current = false; pending[0](['ohos.permission.MICROPHONE']);
  assert.deepEqual(await a, ['TYPE_AUDIO_CAPTURE']); assert.equal(await canceled, false);
  await flush(); assert.deepEqual(prompts[1], [APPROX, PRECISE]);
  pending[1]([APPROX, PRECISE]); assert.equal(await b, true);
});

test('a failed system prompt releases the shared queue and background queued work never prompts', async () => {
  const load = createLoader();
  const { HarmonyGeolocationPermissionGateway } = load('main/ets/capabilities/permissions/HarmonyGeolocationPermissionGateway');
  const context = {}, lifecycle = applicationLifecycle(load), prompts = [], pending = [];
  lifecycle.onAbilityCreate({ context }); lifecycle.onAbilityForeground({ context });
  const gateway = new HarmonyGeolocationPermissionGateway(context, {
    has: () => false, request: permissions => {
      prompts.push(permissions); return new Promise((resolve, reject) => pending.push({ resolve, reject }));
    }
  });
  const failed = gateway.request(() => true);
  const checkedFailure = assert.rejects(failed, /native failure/);
  const next = gateway.request(() => true);
  await flush(); pending[0].reject(Error('native failure')); await checkedFailure;
  await flush(); assert.equal(prompts.length, 2);
  const background = gateway.request(() => true);
  const checkedNext = assert.rejects(next, { code: 'APP_IN_BACKGROUND' });
  const checkedBackground = assert.rejects(background, { code: 'APP_IN_BACKGROUND' });
  lifecycle.onAbilityBackground({ context }); pending[1].resolve([APPROX]);
  await Promise.all([checkedNext, checkedBackground]); assert.equal(prompts.length, 2);
});
