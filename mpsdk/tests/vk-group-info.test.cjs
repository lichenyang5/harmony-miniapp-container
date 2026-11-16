const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { createTestSession } = require('./test-session.cjs');

// Reproduce the screenshot through the shipped Binding, native proxy and iframe scripts.
const webGroup = {
  id: 241534146, description: '', members_count: 2, name: '社区名称',
  screen_name: 'club241534146', is_closed: 0, type: 'group',
  is_admin: 0, is_member: 0, is_advertiser: 0,
  photo_50: 'https://example.com/50.jpg', photo_100: 'https://example.com/100.jpg',
  photo_200: 'https://example.com/200.jpg', photo_base: 'https://example.com/base.jpg'
};
const androidGroup = {
  description: '', id: 241534146, is_closed: 'OPEN', members_count: 2, name: '社区名称',
  photo_100: webGroup.photo_100, photo_200: webGroup.photo_200, photo_50: webGroup.photo_50,
  screen_name: 'club241534146', type: 'group'
};

function fixture() {
  const session = createTestSession(createLoader(), { host: {
    applicationInfo: { accessTokenId: 1 },
    resourceManager: { getRawFileContentSync(name) {
      return fs.readFileSync(path.join(__dirname, '../src/main/resources/rawfile', name));
    } }
  } });
  const binding = session.getBinding(), proxy = binding.injections[0].object;
  const requests = [], responses = [], nativeResponses = [], topListeners = [], childListeners = [];
  const childUrl = 'https://mini.example/start?vk_app_id=1&vk_user_id=7&sign=test&vk_platform=mobile_android';
  const frame = { getAttribute: () => childUrl };
  const top = {
    URL, location: new URL('https://vk.ru/app1'), HosBridge: proxy,
    document: { querySelectorAll: () => [frame] },
    console: { log() {}, warn() {}, error() {} }, setTimeout, clearTimeout,
    addEventListener(name, listener) { if (name === 'message') topListeners.push(listener); }
  };
  top.window = top; top.top = top;
  const child = {
    URL, location: new URL(childUrl), top, parent: top,
    document: { title: 'test' }, console: top.console, setTimeout, clearTimeout,
    HosBridge: {
      supportedHandlers: () => proxy.supportedHandlers(),
      onInterceptResponse(json) {
        nativeResponses.push(JSON.parse(json));
        return JSON.parse(JSON.stringify(proxy.onInterceptResponse(json)));
      }
    },
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options.detail; } },
    addEventListener(name, listener) { if (name === 'message') childListeners.push(listener); },
    dispatchEvent(event) {
      if (event.type === 'VKWebAppEvent') responses.push(JSON.parse(JSON.stringify(event.detail)));
      return true;
    }
  };
  child.window = child; frame.contentWindow = child;
  top.postMessage = data => {
    if (data.type !== 'vk-connect') return;
    const event = { source: child, origin: 'https://mini.example', data,
      stopImmediatePropagation() { throw new Error('GetGroupInfo must stay on the VK Web request path'); } };
    topListeners.forEach(listener => listener(event));
    requests.push(JSON.parse(JSON.stringify(data)));
  };
  vm.runInNewContext(binding.scripts[3].script, top);
  vm.runInNewContext(binding.scripts[2].script, child);
  vm.runInNewContext(binding.scripts[3].script, child);
  return { session, proxy, child, top, requests, responses, nativeResponses,
    receive(data, overrides = {}) {
      let stopped = false;
      const event = { source: top, origin: 'https://vk.ru', data,
        stopImmediatePropagation() { stopped = true; }, ...overrides };
      childListeners.forEach(listener => listener(event));
      return stopped;
    }
  };
}

test('GetGroupInfo crosses the actual Web request and iframe response scripts with Android fields', () => {
  const f = fixture();
  try {
    f.child.AndroidBridge.VKWebAppGetGroupInfo(JSON.stringify({ group_id: webGroup.id, request_id: 'group-request' }));
    assert.deepEqual(f.requests, [{ type: 'vk-connect', handler: 'VKWebAppGetGroupInfo',
      params: { group_id: webGroup.id, request_id: 'group-request' }, connectVersion: '3.0.2' }]);
    const event = { type: 'VKWebAppGetGroupInfoResult', data: { ...webGroup, request_id: 'group-request' } };
    assert.equal(f.receive(event), true);
    assert.deepEqual(f.nativeResponses, [event]);
    assert.deepEqual(f.responses, [{ type: event.type, data: { group: androidGroup, request_id: 'group-request' } }]);
    assert.equal(f.responses.length, 1);
    assert.deepEqual(event.data, { ...webGroup, request_id: 'group-request' });
  } finally { f.session.close(); }
});

test('GetGroupInfo iframe dispatch preserves numeric and empty request ids and already adapted results', () => {
  const f = fixture();
  try {
    for (const request_id of [0, 42, '', 'next']) {
      f.receive({ type: 'VKWebAppGetGroupInfoResult', data: { ...webGroup, request_id } });
      assert.deepEqual(f.responses.at(-1).data, { group: androidGroup, request_id });
    }
    f.receive({ type: 'VKWebAppGetGroupInfoResult', data: { ...webGroup } });
    assert.deepEqual(f.responses.at(-1).data, { group: androidGroup });
    const wrapped = { type: 'VKWebAppGetGroupInfoResult', data: { group: androidGroup, request_id: 'wrapped' } };
    f.receive(wrapped);
    assert.deepEqual(f.responses.at(-1), wrapped);
  } finally { f.session.close(); }
});

test('GetGroupInfo iframe handles CLOSED and PRIVATE without inventing restricted fields', () => {
  const f = fixture();
  try {
    for (const [is_closed, state] of [[0, 'OPEN'], [1, 'CLOSED'], [2, 'PRIVATE']]) {
      f.receive({ type: 'VKWebAppGetGroupInfoResult', data: { ...webGroup, is_closed, request_id: state } });
      assert.deepEqual(f.responses.at(-1).data, { group: { ...androidGroup, is_closed: state }, request_id: state });
    }
    const privateGroup = { ...webGroup, is_closed: 2 };
    delete privateGroup.description; delete privateGroup.members_count; delete privateGroup.is_member;
    f.receive({ type: 'VKWebAppGetGroupInfoResult', data: { ...privateGroup, request_id: 'private' } });
    const expected = { ...androidGroup, is_closed: 'PRIVATE' };
    delete expected.description; delete expected.members_count;
    assert.deepEqual(f.responses.at(-1).data, { group: expected, request_id: 'private' });
  } finally { f.session.close(); }
});

test('GetGroupInfo keeps documented string and multiple parameters on the VK Web request path', () => {
  const f = fixture();
  try {
    for (const params of [{ group_id: String(webGroup.id), request_id: 'string' },
      { group_ids: '241534146,1', request_id: 'multiple' }]) {
      f.child.AndroidBridge.VKWebAppGetGroupInfo(JSON.stringify(params));
      assert.deepEqual(f.requests.at(-1).params, params);
    }
  } finally { f.session.close(); }
});

test('GetGroupInfo iframe dispatch keeps failures and unverified or malformed results unchanged', () => {
  const f = fixture();
  try {
    const missingPhoto = { ...webGroup }; delete missingPhoto.photo_200;
    const events = [
      { type: 'VKWebAppGetGroupInfoFailed', data: { error_type: 'client_error',
        error_data: { error_code: 11, error_reason: 'Access denied' }, request_id: 'failed' } },
      { type: 'VKWebAppGetGroupInfoFailed', data: { error_type: 'client_error',
        error_data: { error_code: 5, error_reason: 'This action cannot be performed in the background' },
        request_id: 'background' } },
      ...[3, -1, 0.5, '0', null].map(is_closed => ({ type: 'VKWebAppGetGroupInfoResult', data: { ...webGroup, is_closed } })),
      { type: 'VKWebAppGetGroupInfoResult', data: { ...webGroup, is_closed: 2, description: null } },
      { type: 'VKWebAppGetGroupInfoResult', data: { ...webGroup, is_closed: 2, members_count: null } },
      { type: 'VKWebAppGetGroupInfoResult', data: { result: [webGroup], request_id: 'multiple' } },
      { type: 'VKWebAppGetGroupInfoResult', data: missingPhoto }
    ];
    for (const event of events) {
      assert.equal(f.receive(event), true);
      assert.deepEqual(f.responses.at(-1), event);
    }
  } finally { f.session.close(); }
});

test('GetGroupInfo iframe ignores untrusted sources and does not adapt after session disposal', () => {
  const f = fixture();
  try {
    const event = { type: 'VKWebAppGetGroupInfoResult', data: { ...webGroup } };
    assert.equal(f.receive(event, { source: {} }), false);
    assert.equal(f.receive(event, { origin: 'https://other.example' }), false);
    assert.equal(f.nativeResponses.length, 0);
    assert.equal(f.responses.length, 0);
    f.session.close();
    assert.equal(f.receive(event), true);
    assert.deepEqual(f.responses, [event]);
  } finally { f.session.close(); }
});
