const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');
const { applicationLifecycle } = require('./application-lifecycle.cjs');

async function flush() { for (let i = 0; i < 20; i++) await Promise.resolve(); }

function fixture(options = {}) {
  const load = options.load ?? createLoader();
  const { MiniAppSDK } = load('main/ets/core/MiniAppSDK');
  const { VkAdapter } = load('main/ets/vendors/vk/VkAdapter');
  const ability = options.ability ?? { applicationInfo: { accessTokenId: 1 } };
  if (!options.uninitialized) {
    const lifecycle = applicationLifecycle(load);
    lifecycle.onAbilityCreate({ context: ability });
    if (!options.background) lifecycle.onAbilityForeground({ context: ability });
  }
  const sent = [];
  let closes = 0, releases = 0;
  const adapter = new VkAdapter();
  adapter.createSwipeBackController = () => ({ setEnabled() {}, dispose() { releases++; } });
  const session = MiniAppSDK.createSession({
    appId: 'same-app', vendor: 'vk', url: 'https://vk.ru/pitprime_shop', uiAbilityContext: ability, uiContext: {},
    onClose: options.missingHost ? undefined : () => { closes++; options.onClose?.(); }
  }, adapter);
  session.attach({ async evaluate(script) {
    new Function('window', script)({ atomicBridge: { postResponse(id, data) { sent.push({ id, data }); } } });
    return '';
  }, pauseAllMedia() {} });
  const binding = session.getBinding();
  const proxy = binding.injections[0].object;
  return { load, ability, session, binding, proxy, sent, closes: () => closes, releases: () => releases,
    request(params = {}, method = 'VKWebAppClose') {
      return proxy.onInterceptRequest(JSON.stringify({ type: 'vk-connect', handler: method,
        params: { ...params, request_id: 42 } }), 'close-route');
    } };
}

test('Close is intercepted and releases only its session, regardless of swipe settings', async () => {
  for (const params of [{}, { status: 'success' }, { status: 'failed', payload: { value: 1 } }]) {
    const f = fixture(), other = fixture({ load: f.load, ability: f.ability });
    f.session.enableBackPressHandling();
    f.session.setSwipeBackEnabled(false);
    assert.equal(f.request(params).intercept, true);
    await flush();
    assert.equal(f.closes(), 1);
    assert.equal(f.releases(), 1);
    assert.throws(() => f.session.getBinding(), { code: 'SESSION_CLOSED' });
    assert.equal(other.closes(), 0);
    assert.ok(other.session.getBinding());
    f.session.requestClose(); f.session.close();
    assert.equal(f.closes(), 1);
    assert.equal(f.sent.length, 0, 'destroyed document must not receive a late success');
    assert.equal(f.request(params).intercept, true, 'late Close must not fall through to VK during view removal');
    other.session.close();
    assert.equal(other.closes(), 0, 'ordinary teardown must not request host navigation');
  }
});

test('Close validates optional parameters without closing or forwarding invalid requests', async () => {
  const f = fixture();
  try {
    for (const params of [{ status: null }, { status: '' }, { status: 'SUCCESS' }, { status: 1 },
      { payload: null }, { payload: [] }, { payload: 'x' }]) {
      f.sent.length = 0;
      assert.equal(f.request(params).intercept, true);
      await flush();
      assert.equal(f.closes(), 0);
      assert.equal(f.sent[0].data.type, 'VKWebAppCloseFailed');
      assert.equal(f.sent[0].data.data.request_id, 42);
      assert.equal(f.sent[0].data.data.error_data.error_code, 5);
    }
    assert.equal(f.request({}, 'VKWebAppUnregisteredExample').intercept, false);
  } finally { f.session.close(); }
});

test('background Close returns client 9 and retains the container', async () => {
  const f = fixture({ background: true });
  try {
    assert.equal(f.request().intercept, true);
    await flush();
    assert.equal(f.closes(), 0);
    assert.equal(f.sent[0].data.data.error_data.error_code, 9);
  } finally { f.session.close(); }
});

test('malformed Close envelopes are consumed before and after disposal; other malformed requests still pass', () => {
  const f = fixture();
  for (const closed of [false, true]) {
    if (closed) f.session.close();
    for (const params of [undefined, null, [], { request_id: null }]) {
      const response = f.proxy.onInterceptRequest(JSON.stringify({ type: 'vk-connect', handler: 'VKWebAppClose', params }), 'invalid-route');
      assert.equal(response.intercept, true);
      assert.equal(Number.isInteger(response.timeout), true);
      const other = f.proxy.onInterceptRequest(JSON.stringify({ type: 'vk-connect', handler: 'Other', params: null }), 'other-route');
      assert.equal(other.intercept, false);
      assert.equal(f.closes(), 0);
    }
  }
});

test('uninitialized lifecycle rejects Close without destroying or forwarding', async () => {
  const f = fixture({ uninitialized: true });
  try {
    assert.equal(f.request().intercept, true);
    await flush();
    assert.equal(f.closes(), 0);
    assert.equal(f.sent[0].data.data.error_data.error_code, 1);
  } finally { f.session.close(); }
});

test('document change drops a pending Close failure instead of delivering it to the new page', async () => {
  const f = fixture();
  try {
    assert.equal(f.request({ status: 'invalid' }).intercept, true);
    f.session.beginDocument('https://vk.ru/pitprime_shop');
    await flush();
    assert.equal(f.sent.length, 0);
    assert.equal(f.closes(), 0);
  } finally { f.session.close(); }
});

test('missing close receiver fails locally and host callback failure never reopens the session', async () => {
  const absent = fixture({ missingHost: true });
  assert.equal(absent.request().intercept, true);
  await flush();
  assert.equal(absent.closes(), 0);
  assert.equal(absent.sent[0].data.type, 'VKWebAppCloseFailed');
  assert.ok(absent.session.getBinding());
  absent.session.close();
  const throwing = fixture({ onClose() { throw new Error('host route failed'); } });
  assert.equal(throwing.request().intercept, true);
  await flush();
  assert.equal(throwing.closes(), 1);
  assert.equal(throwing.releases(), 1);
  throwing.session.requestClose();
  assert.equal(throwing.closes(), 1);
});

test('existing injected capture listener stops Close before the VK host handler', async () => {
  const f = fixture();
  const listeners = [], source = { postMessage() {} };
  const ctx = { URL, location: new URL('https://vk.ru/pitprime_shop'), HosBridge: f.proxy,
    document: { querySelectorAll: () => [{ contentWindow: source,
      getAttribute: () => 'https://mini.example/?vk_app_id=123&vk_user_id=7&sign=test' }] },
    console: { log() {}, error() {} }, setTimeout: () => 1, clearTimeout() {},
    addEventListener(name, fn) { if (name === 'message') listeners.push(fn); } };
  ctx.window = ctx; ctx.top = ctx;
  vm.runInNewContext(f.binding.scripts[3].script, ctx);
  let stopped = false, vkCalls = 0;
  const event = { source, origin: 'https://mini.example',
    data: { type: 'vk-connect', handler: 'VKWebAppClose', params: { status: 'success' } },
    stopImmediatePropagation() { stopped = true; } };
  for (let attempt = 0; attempt < 2; attempt++) {
    stopped = false;
    for (const listener of [...listeners, () => vkCalls++]) {
      listener(event);
      if (stopped) break;
    }
    assert.equal(stopped, true, 'initial and queued Close must both stop in the capture listener');
  }
  await flush();
  assert.equal(stopped, true);
  assert.equal(vkCalls, 0);
  assert.equal(f.closes(), 1);
});

test('host goBack proxy forwards only while its session is active', () => {
  const f = fixture();
  let calls = 0;
  f.session.handleHostGoBack = () => calls++;

  assert.equal(f.binding.injections[0].methods.includes('onHostGoBack'), true);
  f.proxy.onHostGoBack();
  assert.equal(calls, 1);

  f.session.close();
  f.proxy.onHostGoBack();
  assert.equal(calls, 1);
});

test('header close proxy closes only its session once without consulting history or swipe policy', () => {
  const f = fixture(), other = fixture({ load: f.load, ability: f.ability });
  f.session.enableBackPressHandling();
  f.session.setSwipeBackEnabled(false);
  f.session.handleHostGoBack = () => assert.fail('close must not navigate back');
  assert.ok(f.binding.injections[0].methods.includes('onHostClose'));
  f.proxy.onHostClose();
  f.proxy.onHostClose();
  assert.equal(f.closes(), 1);
  assert.equal(f.releases(), 1);
  assert.equal(other.closes(), 0);
  assert.ok(other.session.getBinding());
  other.session.close();
});

test('header close proxy consumes inactive, background and failed close calls', () => {
  for (const options of [{ background: true }, { uninitialized: true }, { missingHost: true }, {}]) {
    const f = fixture(options);
    if (Object.keys(options).length === 0) f.session.close();
    assert.doesNotThrow(() => f.proxy.onHostClose());
    assert.equal(f.closes(), 0);
    f.session.close();
  }
});
