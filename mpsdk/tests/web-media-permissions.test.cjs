const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { applicationLifecycle } = require('./application-lifecycle.cjs');
const AUDIO = 'TYPE_AUDIO_CAPTURE', VIDEO = 'TYPE_VIDEO_CAPTURE';
const MIC = 'ohos.permission.MICROPHONE', CAM = 'ohos.permission.CAMERA';
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };

test('ArkWeb request adapter forwards origin, resources, grants and denial to the original request', () => {
  const { ArkWebMediaRequest } = createLoader()('main/ets/web/ArkWebMediaRequest');
  const original = request([AUDIO, VIDEO]);
  const adapted = new ArkWebMediaRequest(original);
  assert.equal(adapted.getOrigin(), 'https://vk.ru');
  assert.deepEqual(adapted.getAccessibleResource(), [AUDIO, VIDEO]);
  adapted.grant([AUDIO]);
  adapted.deny();
  assert.deepEqual(original.results, [[AUDIO], 'denied']);
});

function request(resources = [AUDIO], origin = 'https://vk.ru') {
  const results = [];
  return { results, getOrigin: () => origin, getAccessibleResource: () => resources,
    grant: values => results.push(values), deny: () => results.push('denied') };
}

function permissionFixture() {
  const load = createLoader();
  const { WebMediaPermissionController } = load('main/ets/web/WebMediaPermissionController');
  const pending = [];
  let foreground = true;
  const gateway = {
    assertForeground() { if (!foreground) throw Error('background'); },
    request(resources, isCurrent) { return new Promise((resolve, reject) => pending.push({ resources, isCurrent, resolve, reject })); }
  };
  const controller = new WebMediaPermissionController(gateway, origin => origin === 'https://vk.ru');
  controller.beginDocument('https://vk.ru');
  return { controller, pending, background() { foreground = false; } };
}

test('grants only requested media resources after permission completion', async () => {
  const f = permissionFixture(), r = request();
  f.controller.handle(r);
  assert.deepEqual(r.results, []);
  f.pending[0].resolve([AUDIO, VIDEO]);
  await flush();
  assert.deepEqual(r.results, [[AUDIO]]);
});

test('denies foreign origins, unsupported resources and background without requesting the OS', () => {
  const f = permissionFixture();
  for (const r of [request([AUDIO], 'https://evil.example'), request(['TYPE_MIDI_SYSEX']), request([])]) {
    f.controller.handle(r);
    assert.deepEqual(r.results, ['denied']);
  }
  f.background();
  const r = request(); f.controller.handle(r);
  assert.deepEqual(r.results, ['denied']);
  assert.equal(f.pending.length, 0);
});

test('partial system permission and system failure deny each web request once', async () => {
  for (const fails of [false, true]) {
    const f = permissionFixture(), r = request([AUDIO, VIDEO]);
    f.controller.handle(r);
    if (fails) f.pending[0].reject(Error('private system failure'));
    else f.pending[0].resolve([AUDIO]);
    await flush();
    assert.deepEqual(r.results, ['denied']);
  }
});

test('navigation, disposal and background prevent late grants; cleanup is idempotent', async () => {
  for (const transition of ['navigation', 'dispose', 'background']) {
    const f = permissionFixture(), r = request();
    f.controller.handle(r);
    if (transition === 'navigation') f.controller.beginDocument('https://vk.ru');
    if (transition === 'dispose') { f.controller.dispose(); f.controller.dispose(); }
    if (transition === 'background') f.background();
    assert.equal(f.pending[0].isCurrent(), false);
    f.pending[0].resolve([AUDIO]); await flush();
    assert.deepEqual(r.results, ['denied']);
    if (transition === 'dispose') {
      f.controller.beginDocument('https://vk.ru');
      const next = request(); f.controller.handle(next);
      assert.deepEqual(next.results, ['denied']);
    }
  }
});

test('untrusted top document cannot grant to an otherwise allowed iframe origin', () => {
  const f = permissionFixture(), r = request();
  f.controller.beginDocument('https://evil.example');
  f.controller.handle(r);
  assert.deepEqual(r.results, ['denied']);
  assert.equal(f.pending.length, 0);
});

test('a broken request callback cannot block cleanup or another instance', async () => {
  const f = permissionFixture(), other = permissionFixture(), r = request(), r2 = request();
  f.controller.handle({ ...request(), deny() { throw Error('detached'); } });
  f.controller.handle(r); other.controller.handle(r2);
  assert.doesNotThrow(() => f.controller.dispose());
  assert.deepEqual(r.results, ['denied']);
  other.pending[0].resolve([AUDIO]); await flush();
  assert.deepEqual(r2.results, [[AUDIO]]);
});

test('native gateway maps only needed permissions, serializes same-host prompts and skips stale queued work', async () => {
  const load = createLoader();
  const { HarmonyMediaPermissionGateway } = load('main/ets/capabilities/media/HarmonyMediaPermissionGateway');
  const context = { applicationInfo: { accessTokenId: 1 } };
  const lifecycle = applicationLifecycle(load);
  lifecycle.onAbilityCreate({ context }); lifecycle.onAbilityForeground({ context });
  const prompts = [], pending = [];
  const access = { has: () => false, request: permissions => {
    prompts.push(permissions); return new Promise(resolve => pending.push(resolve));
  } };
  const first = new HarmonyMediaPermissionGateway(context, access);
  const second = new HarmonyMediaPermissionGateway(context, access);
  let current = true;
  const a = first.request([AUDIO], () => true);
  const b = second.request([VIDEO], () => current);
  await flush(); assert.deepEqual(prompts, [[MIC]]);
  current = false; pending[0]([MIC]);
  assert.deepEqual(await a, [AUDIO]); assert.deepEqual(await b, []);
  assert.equal(prompts.length, 1);
  const c = second.request([AUDIO, VIDEO], () => true);
  await flush(); assert.deepEqual(prompts[1], [MIC, CAM]);
  pending[1]([MIC, CAM]); assert.deepEqual(await c, [AUDIO, VIDEO]);
});

test('native gateway handles existing permission, denial, background and independent hosts', async () => {
  const load = createLoader();
  const { HarmonyMediaPermissionGateway } = load('main/ets/capabilities/media/HarmonyMediaPermissionGateway');
  const life = applicationLifecycle(load), a = {}, b = {};
  for (const context of [a, b]) { life.onAbilityCreate({ context }); life.onAbilityForeground({ context }); }
  const allowed = new HarmonyMediaPermissionGateway(a, { has: () => true, request() { throw Error('unexpected prompt'); } });
  assert.deepEqual(await allowed.request([AUDIO], () => true), [AUDIO]);
  const blocked = new HarmonyMediaPermissionGateway(a, { has: () => false, request: () => new Promise(() => {}) });
  blocked.request([VIDEO], () => true);
  const independent = new HarmonyMediaPermissionGateway(b, { has: () => false, request: async () => [] });
  assert.deepEqual(await independent.request([AUDIO], () => true), []);
  life.onAbilityBackground({ context: b });
  await assert.rejects(independent.request([AUDIO], () => true), { code: 'APP_IN_BACKGROUND' });
});
