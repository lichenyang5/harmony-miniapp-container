const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');
const { createTestSession } = require('./test-session.cjs');

const launchUrl = 'https://mini.example/start?vk_app_id=1&vk_user_id=7&sign=test&vk_platform=mobile_web&empty=&tag=a&tag=b&__proto__=safe&text=%E4%BD%A0%E5%A5%BD';
function fixture(load = createLoader()) {
  const session = createTestSession(load);
  const binding = session.getBinding(), proxy = binding.injections[0].object;
  const source = {}, listeners = [], messages = [], childListeners = [];
  const frame = { contentWindow: source, getAttribute: () => launchUrl };
  const top = { URL, location: new URL('https://vk.ru/app1'), HosBridge: proxy,
    document: { querySelectorAll: () => [frame] },
    console: { log() {}, error() {} }, setTimeout, clearTimeout,
    addEventListener(name, callback) { if (name === 'message') listeners.push(callback); } };
  top.window = top; top.top = top;
  vm.runInNewContext(binding.scripts[3].script, top);
  const child = { URL, location: new URL(launchUrl), document: { title: 'test' },
    console: top.console, setTimeout, clearTimeout,
    addEventListener(name, callback) { if (name === 'message') childListeners.push(callback); },
    parent: { postMessage(data) { messages.push(data); } }, top };
  child.window = child;
  child.history = { state: null, replaceState(_state, _title, url) { child.location = new URL(url); } };
  return { load, session, binding, proxy, child, source, messages, childListeners,
    inject() { vm.runInNewContext(binding.scripts[3].script, child); },
    deliver(data = messages[0], overrides = {}) {
      let stopped = false;
      const event = { source, origin: 'https://mini.example', data,
        stopImmediatePropagation() { stopped = true; }, ...overrides };
      for (const callback of listeners) callback(event);
      return stopped;
    } };
}

test('iframe reports all decoded launch values after platform adaptation through the existing top listener', () => {
  const f = fixture();
  try {
    f.inject();
    assert.equal(f.messages.length, 1);
    assert.equal(f.deliver(), true);
    const params = f.binding.launchParams;
    assert.equal(params.get('vk_app_id'), '1');
    assert.equal(params.get('vk_user_id'), '7');
    assert.equal(params.get('vk_platform'), 'mobile_android');
    assert.equal(params.get('empty'), '');
    assert.equal(params.get('missing'), undefined);
    assert.equal(params.get('__proto__'), 'safe');
    assert.equal(params.get('text'), '你好');
    assert.deepEqual(params.getAll('tag'), ['a', 'b']);
    assert.equal(params.getEntries().length, new URL(launchUrl).searchParams.size);
    f.inject();
    assert.equal(f.messages.length, 1, 'do not report twice in one document');
    const copy = params.getEntries(); copy[0].value = 'changed';
    params.getAll('tag').push('changed');
    assert.equal(params.get('vk_app_id'), '1');
    assert.deepEqual(params.getAll('tag'), ['a', 'b']);
  } finally { f.session.close(); }
});

test('unrelated sources, origins and different iframe app ids cannot replace stored parameters', () => {
  const f = fixture();
  try {
    f.inject();
    f.deliver(undefined, { source: {} });
    f.deliver(undefined, { origin: 'https://other.example' });
    const wrong = JSON.parse(JSON.stringify(f.messages[0]));
    wrong.params.find(item => item.name === 'vk_app_id').value = '2';
    f.deliver(wrong);
    assert.equal(f.binding.launchParams.get('vk_app_id'), undefined);
    f.deliver();
    assert.equal(f.binding.launchParams.get('vk_app_id'), '1');
  } finally { f.session.close(); }
});

test('launch parameters are session scoped and cleared on top document changes and disposal', () => {
  const f = fixture(), other = fixture(f.load);
  f.inject(); f.deliver();
  assert.equal(other.binding.launchParams.get('vk_user_id'), undefined);
  f.session.beginDocument('https://vk.ru/app1');
  assert.equal(f.binding.launchParams.get('vk_user_id'), undefined);
  f.deliver();
  assert.equal(f.binding.launchParams.get('vk_user_id'), '7');
  f.session.close();
  assert.equal(f.binding.launchParams.get('vk_user_id'), undefined);
  assert.equal(f.proxy.onMiniAppLaunchParams('https://vk.ru/app1', JSON.stringify(f.messages[0].params)), false);
  other.session.close();
});

test('native launch reporting rejects invalid payloads and unrelated apps without losing valid data', () => {
  const f = fixture();
  try {
    f.inject(); f.deliver();
    for (const value of ['invalid', 'null', '{}', '[null]', '[{"name":"x","value":4}]', '[]']) {
      assert.equal(f.proxy.onMiniAppLaunchParams('https://vk.ru/app1', value), false);
    }
    assert.equal(f.proxy.onMiniAppLaunchParams('https://vk.ru/feed', JSON.stringify(f.messages[0].params)), false);
    assert.equal(f.binding.launchParams.get('vk_user_id'), '7');
  } finally { f.session.close(); }
});

test('report failure does not prevent the existing response listener from being installed', () => {
  const f = fixture();
  try {
    f.child.parent.postMessage = () => { throw new Error('unavailable'); };
    assert.doesNotThrow(() => f.inject());
    assert.equal(f.childListeners.length, 1);
    assert.equal(f.child.__vkLaunchParamsReported, undefined);
  } finally { f.session.close(); }
});

test('iframe documents without launch parameters do not report', () => {
  const f = fixture();
  try {
    f.child.location = new URL('https://mini.example/other');
    f.inject();
    assert.equal(f.messages.length, 0);
  } finally { f.session.close(); }
});
