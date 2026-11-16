const { applicationLifecycle } = require('./application-lifecycle.cjs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const AUDIO = 'TYPE_AUDIO_CAPTURE';
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };

function fixture(load = createLoader(), vendor) {
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { VkVendor } = load('main/ets/vendors/vk/VkVendor');
  const { VkAdapter } = load('main/ets/vendors/vk/VkAdapter');
  const { SessionWebMediaPermissions } = load('main/ets/web/SessionWebMediaPermissions');
  const adapter = new VkAdapter();
  const session = new MiniAppSession('media-session', {
    info: { appId: 'same-app', vendor: 'vk', url: 'https://vk.ru/call?id=123' },
    vendor: vendor ?? new VkVendor(), adapter,
    swipeBackController: { setEnabled() {}, dispose() {} }
  }, { applicationInfo: { accessTokenId: 1 } });
  const host = applicationLifecycle(load);
  host.onAbilityCreate({ context: session.uiAbilityContext });
  host.onAbilityForeground({ context: session.uiAbilityContext });
  session.attach({ evaluate: async () => '', pauseAllMedia() {} });
  const pending = [];
  const media = new SessionWebMediaPermissions(session, {
    assertForeground() {},
    request(resources, isCurrent) { return new Promise(resolve => pending.push({ resources, isCurrent, resolve })); }
  });
  const navigate = address => { session.beginDocument(address); media.beginDocument(address); };
  navigate(session.initialUrl);
  return { session, media, pending, navigate };
}

function request(origin = 'https://vk.ru') {
  const results = [];
  return { results, getOrigin: () => origin, getAccessibleResource: () => [AUDIO],
    grant: resources => results.push(resources), deny: () => results.push('denied') };
}

test('a document that begins in background can request media after resume, and late background grants are denied', async () => {
  const load = createLoader(); const f = fixture(load);
  const host = applicationLifecycle(load), ability = { context: f.session.uiAbilityContext };
  host.onAbilityBackground(ability);
  f.navigate('https://vk.ru/next');
  const hidden = request(); f.media.handle(hidden); assert.deepEqual(hidden.results, ['denied']);
  host.onAbilityForeground(ability);
  const resumed = request(); f.media.handle(resumed); assert.equal(f.pending.length, 1);
  host.onAbilityBackground(ability);
  f.pending[0].resolve([AUDIO]); await flush(); assert.deepEqual(resumed.results, ['denied']);
  host.onAbilityForeground(ability);
  const retry = request(); f.media.handle(retry);
  f.pending[1].resolve([AUDIO]); await flush(); assert.deepEqual(retry.results, [[AUDIO]]);
  f.media.dispose(); f.session.close();
});

test('generic session permissions use the real VK binding policy without a VK dependency in the view', async () => {
  const f = fixture(), r = request();
  f.media.handle(r);
  assert.equal(f.pending.length, 1);
  f.pending[0].resolve([AUDIO]); await flush();
  assert.deepEqual(r.results, [[AUDIO]]);
  const foreign = request('https://miniapp.example'); f.media.handle(foreign);
  assert.equal(f.pending.length, 2);
  assert.deepEqual(foreign.results, []);
  f.pending[1].resolve([AUDIO]); await flush();
  assert.deepEqual(foreign.results, [[AUDIO]]);
  f.media.dispose(); f.session.close();
});

test('a vendor without a media policy defaults to denial', () => {
  const f = fixture(createLoader(), { vendorId: 'other', createBinding: () => ({
    injections: [], scripts: [], onDocumentChanged() {}, dispose() {}
  }) });
  const r = request(); f.media.handle(r);
  assert.deepEqual(r.results, ['denied']); assert.equal(f.pending.length, 0);
  f.media.dispose(); f.session.close();
});

test('every session document change invalidates pending grants, including before the next view callback', async () => {
  const f = fixture();
  for (let i = 0; i < 3; i++) {
    const r = request(); f.media.handle(r);
    const pending = f.pending[i];
    f.session.beginDocument('https://vk.ru/call?id=456');
    assert.deepEqual(r.results, ['denied']);
    assert.equal(pending.isCurrent(), false);
    pending.resolve([AUDIO]); await flush();
    assert.deepEqual(r.results, ['denied']);
    f.media.beginDocument('https://vk.ru/call?id=456');
  }
  f.media.dispose(); f.session.close();
});

test('session close before view unmount denies immediately and cannot authorize later requests', async () => {
  const f = fixture(), r = request(); f.media.handle(r);
  f.session.close();
  assert.deepEqual(r.results, ['denied']);
  f.pending[0].resolve([AUDIO]); await flush();
  const after = request(); f.media.handle(after);
  assert.deepEqual(after.results, ['denied']);
  assert.deepEqual(r.results, ['denied']);
  f.media.dispose();
});

test('closing one same-app session or disposing a view leaves the other session usable', async () => {
  const load = createLoader(), first = fixture(load), second = fixture(load);
  const a = request(), b = request();
  first.media.handle(a); second.media.handle(b);
  first.media.dispose(); first.media.dispose();
  first.pending[0].resolve([AUDIO]); second.pending[0].resolve([AUDIO]); await flush();
  assert.deepEqual(a.results, ['denied']); assert.deepEqual(b.results, [[AUDIO]]);
  first.media.beginDocument('https://vk.ru');
  const late = request(); first.media.handle(late); assert.deepEqual(late.results, ['denied']);
  first.session.close(); second.media.dispose(); second.session.close();
});

test('non-VK top documents and frames still require system media permission', async () => {
  const f = fixture(), r = request();
  f.navigate('https://miniapp.example'); f.media.handle(r);
  assert.deepEqual(r.results, []); assert.equal(f.pending.length, 1);
  f.pending[0].resolve([]); await flush();
  assert.deepEqual(r.results, ['denied']);
  const frame = request('https://frame.example'); f.media.handle(frame);
  assert.deepEqual(frame.results, []); assert.equal(f.pending.length, 2);
  f.pending[1].resolve([AUDIO]); await flush();
  assert.deepEqual(frame.results, [[AUDIO]]);
  f.media.dispose(); f.session.close();
});
