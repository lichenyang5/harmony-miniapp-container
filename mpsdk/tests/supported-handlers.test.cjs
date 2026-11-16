const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { createTestSession } = require('./test-session.cjs');

const defaults = ['VKWebAppInit', 'VKWebAppGetConfig', 'VKWebAppGetUserInfo'];
const resourceName = 'vk/supported-handlers.json';
const preset = handlers => JSON.stringify({ version: 1, supportedHandlers: handlers });

function fixture({ load = createLoader(), adapter, read = () => preset(defaults) } = {}) {
  const reads = [];
  const host = { applicationInfo: { accessTokenId: 1 }, resourceManager: {
    getRawFileContentSync(name) {
      reads.push(name);
      return Buffer.from(read(name));
    }
  } };
  const session = createTestSession(load, { host, adapter });
  const binding = session.getBinding();
  const proxy = binding.injections[0].object;
  return { load, session, binding, proxy, reads,
    respond(handlers) {
      return proxy.onInterceptResponse(JSON.stringify({ type: 'SetSupportedHandlers',
        data: { supportedHandlers: handlers } }));
    }
  };
}

test('binding reads the shipped resource before the first supported query', () => {
  const shipped = JSON.parse(fs.readFileSync(path.join(__dirname,
    '../src/main/resources/rawfile', resourceName), 'utf8'));
  assert.equal(shipped.version, 1);
  assert.ok(Array.isArray(shipped.supportedHandlers));
  assert.ok(shipped.supportedHandlers.every(name => typeof name === 'string'));
  for (const name of defaults) assert.ok(shipped.supportedHandlers.includes(name));
  const f = fixture({ read: name => fs.readFileSync(path.join(__dirname, '../src/main/resources/rawfile', name)) });
  try {
    assert.deepEqual(f.reads, [resourceName]);
    const expected = [...new Set(shipped.supportedHandlers)]
      .filter(name => !(shipped.unsupportedHandlers || []).includes(name));
    assert.deepEqual(f.proxy.supportedHandlers().slice(0, expected.length), expected);
    assert.ok(shipped.unsupportedHandlers.includes('VKWebAppOpenWallPost'));
    assert.equal(f.proxy.supportedHandlers().includes('VKWebAppOpenWallPost'), false);
    assert.ok(f.proxy.supportedHandlers().includes('VKWebAppOpenCodeReader'));
    assert.equal(f.proxy.onInterceptRequest(JSON.stringify({ type: 'vk-connect',
      handler: 'VKWebAppGetUserInfo', params: {} }), 'route').intercept, false);
  } finally { f.session.close(); }
});

test('valid preset is authoritative, deduplicated and retains spelling and order', () => {
  const f = fixture({ read: () => preset(['VKWebAppPresetOnly', 'VKWebAppInit',
    'VKWebAppPresetOnly', ' VKWebAppUntrimmed ']) });
  try {
    const available = f.proxy.supportedHandlers();
    assert.deepEqual(available.slice(0, 3), ['VKWebAppPresetOnly', 'VKWebAppInit', ' VKWebAppUntrimmed ']);
    assert.equal(available.includes('VKWebAppGetConfig'), false);
    assert.equal(available.filter(name => name === 'VKWebAppPresetOnly').length, 1);
  } finally { f.session.close(); }
});

for (const [name, read] of [
  ['missing resource', () => { throw new Error('missing resource'); }],
  ['invalid JSON', () => '{'],
  ['null root', () => 'null'],
  ['array root', () => '[]'],
  ['missing handlers', () => JSON.stringify({ version: 1 })],
  ['non-array handlers', () => JSON.stringify({ version: 1, supportedHandlers: 'VKWebAppBad' })],
  ['non-string entry', () => preset(['VKWebAppBad', 1])],
]) {
  test(`preset ${name} falls back as a whole and keeps native handlers`, () => {
    const f = fixture({ read });
    try {
      assert.deepEqual(f.reads, [resourceName]);
      const available = f.proxy.supportedHandlers();
      assert.deepEqual(available.slice(0, 3), defaults);
      assert.ok(available.includes('VKWebAppOpenCodeReader'));
      assert.equal(available.includes('VKWebAppBad'), false);
    } finally { f.session.close(); }
  });
}

test('valid empty preset preserves only native declarations', () => {
  const f = fixture({ read: () => preset([]) });
  try {
    assert.equal(f.proxy.supportedHandlers().includes('VKWebAppInit'), false);
    assert.ok(f.proxy.supportedHandlers().includes('VKWebAppOpenCodeReader'));
  } finally { f.session.close(); }
});

test('remote responses replace their snapshot and share the proxy merge order', () => {
  const f = fixture();
  try {
    const initial = f.proxy.supportedHandlers();
    const first = f.respond(['VKWebAppRemoteA', 'VKWebAppInit', 'VKWebAppRemoteA']);
    assert.deepEqual(first.data.data.supportedHandlers, [...initial, 'VKWebAppRemoteA']);
    assert.deepEqual(first.data.data.supportedHandlers, f.proxy.supportedHandlers());
    const second = f.respond(['VKWebAppRemoteB']);
    assert.deepEqual(second.data.data.supportedHandlers, [...initial, 'VKWebAppRemoteB']);
    assert.deepEqual(f.proxy.supportedHandlers(), second.data.data.supportedHandlers);
    assert.deepEqual(f.respond([]).data.data.supportedHandlers, initial);
    assert.deepEqual(f.proxy.supportedHandlers(), initial);
  } finally { f.session.close(); }
});

test('invalid remote responses pass through without overwriting valid state', () => {
  const f = fixture();
  try {
    f.respond(['VKWebAppRemoteA']);
    const before = f.proxy.supportedHandlers();
    for (const invalid of [undefined, null, 'bad', [1]]) {
      const result = f.respond(invalid);
      assert.equal(result.intercept, false);
      assert.equal(result.data, undefined);
      assert.deepEqual(f.proxy.supportedHandlers(), before);
    }
  } finally { f.session.close(); }
});

test('shared adapter and same appId reuse the preset read but isolate remote state', () => {
  const load = createLoader();
  const { VkAdapter } = load('main/ets/vendors/vk/VkAdapter');
  const adapter = new VkAdapter();
  const a = fixture({ load, adapter, read: () => preset(['VKWebAppPresetA']) });
  const b = fixture({ load, adapter, read: () => preset(['VKWebAppPresetB']) });
  try {
    const bInitial = b.proxy.supportedHandlers();
    a.respond(['VKWebAppRemoteA']);
    assert.deepEqual(b.proxy.supportedHandlers(), bInitial);
    assert.equal(bInitial.includes('VKWebAppPresetA'), true);
    assert.deepEqual(a.reads, [resourceName]);
    assert.deepEqual(b.reads, []);
    assert.equal(a.proxy.supportedHandlers().includes('VKWebAppPresetB'), false);
    a.session.close();
    assert.deepEqual(a.proxy.supportedHandlers(), []);
    assert.deepEqual(b.proxy.supportedHandlers(), bInitial);
    b.respond(['VKWebAppRemoteB']);
    assert.ok(b.proxy.supportedHandlers().includes('VKWebAppRemoteB'));
  } finally { a.session.close(); b.session.close(); }
});

test('failed preset load is cached across sessions without retrying or exposing a mutable array', () => {
  const load = createLoader();
  const a = fixture({ load, read: () => { throw new Error('missing resource'); } });
  const b = fixture({ load, read: () => preset(['VKWebAppUnexpectedRetry']) });
  try {
    assert.deepEqual(a.reads, [resourceName]);
    assert.deepEqual(b.reads, []);
    assert.deepEqual(a.proxy.supportedHandlers().slice(0, 3), defaults);
    a.proxy.supportedHandlers().splice(0);
    assert.deepEqual(b.proxy.supportedHandlers().slice(0, 3), defaults);
    assert.equal(b.proxy.supportedHandlers().includes('VKWebAppUnexpectedRetry'), false);
  } finally { a.session.close(); b.session.close(); }
});

test('document changes discard remote state while retaining the loaded preset', () => {
  const f = fixture();
  try {
    const initial = f.proxy.supportedHandlers();
    f.respond(['VKWebAppRemoteA']);
    f.session.beginDocument('https://vk.ru/app1?next=1');
    assert.deepEqual(f.proxy.supportedHandlers(), initial);
    assert.deepEqual(f.reads, [resourceName]);
    f.session.close();
    assert.deepEqual(f.proxy.supportedHandlers(), []);
    assert.equal(f.respond(['VKWebAppLate']).data, undefined);
    assert.deepEqual(f.proxy.supportedHandlers(), []);
  } finally { f.session.close(); }
});

test('published snapshots remain unchanged when remote state updates', () => {
  const f = fixture();
  try {
    const response = f.respond(['VKWebAppRemoteA']);
    const before = f.proxy.supportedHandlers();
    response.data.data.supportedHandlers.splice(0);
    assert.deepEqual(f.proxy.supportedHandlers(), before);
    f.respond(['VKWebAppRemoteB']);
    assert.ok(before.includes('VKWebAppRemoteA'));
    assert.equal(before.includes('VKWebAppRemoteB'), false);
    assert.notEqual(f.proxy.supportedHandlers(), before);
    assert.ok(f.proxy.supportedHandlers().includes('VKWebAppRemoteB'));
  } finally { f.session.close(); }
});

test('registry copies remote inputs and available outputs', () => {
  const f = fixture();
  try {
    const remote = ['VKWebAppRemoteA'];
    f.binding.registry.updateRemoteSupportedHandlers(remote);
    const before = f.binding.registry.getAvailableHandlers();
    remote.push('VKWebAppInjected');
    f.binding.registry.getAvailableHandlers().splice(0);
    assert.deepEqual(f.binding.registry.getAvailableHandlers(), before);
    assert.deepEqual(f.binding.registry.getAvailableHandlers(), before);
    assert.deepEqual(f.proxy.supportedHandlers(), before);
    assert.equal(f.binding.registry.getSupportedHandlers().includes('VKWebAppRemoteA'), false);
    f.session.close();
    assert.deepEqual(f.binding.registry.getAvailableHandlers(), []);
  } finally { f.session.close(); }
});

function installAndroidBridge(f, read, sent = []) {
  const window = { top: {}, parent: { postMessage: data => sent.push(data) },
    HosBridge: { supportedHandlers: read } };
  const script = f.binding.scripts.find(item => item.script.includes('window.AndroidBridge = new Proxy'));
  assert.ok(script);
  vm.runInNewContext(script.script, { window, URL,
    location: { href: 'https://miniapp.example/?vk_app_id=1&vk_user_id=2&sign=test' },
    console: { log() {}, warn() {}, error() {} } });
  return window.AndroidBridge;
}

test('AndroidBridge hits stay local and each miss refreshes native at most once', () => {
  const f = fixture();
  let reads = 0;
  const sent = [];
  try {
    const bridge = installAndroidBridge(f, () => { reads++; return f.proxy.supportedHandlers(); }, sent);
    assert.equal(bridge.VKWebAppUnknown, undefined);
    assert.equal(reads, 1);
    const init = bridge.VKWebAppInit;
    for (let i = 0; i < 50; i++) {
      assert.equal(bridge.VKWebAppInit, init);
      assert.equal('VKWebAppInit' in bridge, true);
    }
    init('{}');
    assert.equal(sent.length, 1);
    assert.equal(reads, 1);
    assert.equal('VKWebAppLater' in bridge, false);
    assert.equal(reads, 2);
    f.respond(['VKWebAppLater']);
    assert.equal(typeof bridge.VKWebAppLater, 'function');
    assert.equal(reads, 3);
    assert.equal('VKWebAppLater' in bridge, true);
    assert.equal(reads, 3);
    assert.equal(bridge.then, undefined);
    assert.equal(bridge[Symbol.iterator], undefined);
    assert.equal(reads, 3);
    const nextPage = installAndroidBridge(f, () => { reads++; return f.proxy.supportedHandlers(); });
    assert.equal(typeof nextPage.VKWebAppInit, 'function');
    assert.equal(reads, 4);
  } finally { f.session.close(); }
});

test('AndroidBridge failed refresh preserves positive cache and retries later', () => {
  const f = fixture();
  let fail = false, reads = 0;
  try {
    const bridge = installAndroidBridge(f, () => {
      reads++;
      if (fail) throw new Error('bridge unavailable');
      return f.proxy.supportedHandlers();
    });
    assert.equal(typeof bridge.VKWebAppInit, 'function');
    fail = true;
    assert.equal(bridge.VKWebAppLater, undefined);
    assert.equal(reads, 2);
    assert.equal(typeof bridge.VKWebAppInit, 'function');
    assert.equal(reads, 2);
    fail = false;
    f.respond(['VKWebAppLater']);
    assert.equal(typeof bridge.VKWebAppLater, 'function');
    assert.equal(reads, 3);
  } finally { f.session.close(); }
});


test('unsupported preset entries override preset native and remote declarations', () => {
  const blocked = ['VKWebAppOpenWallPost', 'VKWebAppOpenCodeReader', 'VKWebAppInit'];
  const load = createLoader();
  const read = () => JSON.stringify({ version: 1,
    supportedHandlers: [...defaults, 'VKWebAppOpenWallPost'], unsupportedHandlers: blocked });
  const f = fixture({ load, read });
  const other = fixture({ load, read });
  try {
    assert.ok(f.binding.registry.getSupportedHandlers().includes('VKWebAppOpenCodeReader'));
    for (const session of [f, other]) {
      const response = session.respond([...blocked, 'VKWebAppAllowed']);
      for (const name of blocked) {
        assert.equal(session.proxy.supportedHandlers().includes(name), false);
        assert.equal(response.data.data.supportedHandlers.includes(name), false);
      }
      assert.ok(session.proxy.supportedHandlers().includes('VKWebAppAllowed'));
      const bridge = installAndroidBridge(session, () => session.proxy.supportedHandlers());
      assert.equal(bridge.VKWebAppOpenWallPost, undefined);
      assert.equal('VKWebAppOpenWallPost' in bridge, false);
      session.respond([...blocked, 'VKWebAppAnother']);
      assert.equal(bridge.VKWebAppOpenWallPost, undefined);
      assert.equal(typeof bridge.VKWebAppAnother, 'function');
      session.session.beginDocument('https://vk.ru/app1?next');
      for (const name of blocked) assert.equal(session.proxy.supportedHandlers().includes(name), false);
    }
    assert.deepEqual(f.reads, [resourceName]);
    assert.deepEqual(other.reads, []);
  } finally { f.session.close(); other.session.close(); }
});
