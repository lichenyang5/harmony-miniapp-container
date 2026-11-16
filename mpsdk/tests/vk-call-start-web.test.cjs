const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const scriptPath = path.join(__dirname, '../src/main/ets/vendors/vk/scripts/VkCallStartCompatScript.ets');
function compatScript() {
  const source = fs.readFileSync(scriptPath, 'utf8');
  const literal = source.match(/export const vkCallStartCompatScript: string = (`[\s\S]*`);/);
  assert.ok(literal, 'read the actual SDK injection');
  return vm.runInNewContext(literal[1]);
}

function events(target = {}) {
  const listeners = new Map();
  target.addEventListener = (name, fn) => {
    if (!listeners.has(name)) listeners.set(name, new Set());
    listeners.get(name).add(fn);
  };
  target.removeEventListener = (name, fn) => listeners.get(name)?.delete(fn);
  target.emit = (name, event = {}) => [...(listeners.get(name) || [])].forEach(fn => fn(event));
  target.listenerCount = name => listeners.get(name)?.size || 0;
  return target;
}

function page({ host = 'm.vk.ru', top = true, mobile = true } = {}) {
  const frame = events({ isConnected: true, src: 'https://mini.example/?vk_app_id=123', contentWindow: {} });
  frame.getAttribute = name => name === 'src' ? frame.src : null;
  const container = { querySelector: () => frame };
  const window = events({ isMVK: mobile });
  window.top = top ? window : {};
  const logs = [];
  const sandbox = vm.createContext({
    window, self: window, location: { protocol: 'https:', hostname: host },
    document: { getElementById: () => container },
    console: { info: value => logs.push(value), warn: value => logs.push(value), log: value => logs.push(value) }
  });
  const app = { containerId: 'app', appId: 123, vkApp: { options: { aid: 123, is_calls_available: true } } };
  function install() { vm.runInContext(compatScript(), sandbox); }
  // Same queue lifecycle as webpack: it drains preloaded chunks, then replaces push.
  const modules = new Map();
  const cache = new Map();
  function runtime() {
    const queue = window.webpackChunkvkmvk ||= [];
    const register = chunk => Object.entries(chunk[1]).forEach(([id, factory]) => modules.set(id, factory));
    queue.forEach(register);
    const parentPush = queue.push.bind(queue);
    queue.push = function(chunk) {
      register(chunk);
      const result = parentPush(chunk);
      if (chunk[2]) chunk[2](requireModule);
      return result;
    };
  }
  function requireModule(id) {
    if (cache.has(String(id))) return cache.get(String(id)).exports;
    const module = { exports: {} };
    cache.set(String(id), module);
    modules.get(String(id)).call(module.exports, module, module.exports, requireModule);
    return module.exports;
  }
  function publish(factory, id = 10, executeInsidePush = true) {
    (window.webpackChunkvkmvk ||= []).push([[id], { [id]: factory }, executeInsidePush ? req => req(id) : undefined]);
    return () => requireModule(id);
  }
  return { window, frame, app, logs, install, runtime, publish, sandbox };
}

function officialModule(target, { api, store } = {}) {
  const calls = [];
  const writes = [];
  const u = { isMvk: () => !!target.window.isMVK };
  const g = { ERROR_CODES: { UNSUPPORTED_PLATFORM: 6 }, ERROR_REASONS: { UNSUPPORTED_PLATFORM: 'Unsupported platform' } };
  class BaseHandler {
    constructor() { this.params = {}; }
    setData(params, app) { this.params.request_id = params.request_id; this.app = app; }
    errorHandler(error) {
      this.callback?.({ type: 'VKWebAppCallStartFailed', data: { request_id: this.params.request_id,
        error_type: 'client_error', error_data: { error_code: error.code || 1, error_reason: error.reason || error.message } } });
    }
    successHandler(data) { this.callback?.({ type: 'VKWebAppCallStartResult', data: { ...data, request_id: this.params.request_id } }); }
  }
  class CallStart extends BaseHandler {
    // The exact platform gate from VK's published handler (2026-09-23); service dependencies below are substitutes.
    handler(e,t,a){if(this.setData(e,t),this.callback=a,(0,u.isMvk)())return this.errorHandler({code:g.ERROR_CODES.UNSUPPORTED_PLATFORM,reason:g.ERROR_REASONS.UNSUPPORTED_PLATFORM});this.getCallParams()}
    async getCallParams() {
      const options = target.app.vkApp?.options;
      if (!options?.aid) return this.errorHandler({ reason: 'App is not found!' });
      if (!options.is_calls_available) return this.errorHandler({ code: 11, reason: 'App calls is unavailable!' });
      try {
        calls.push({ method: 'apps.startCall', app_id: options.aid });
        const result = api ? await api(options.aid) : { join_link: 'real-provider-fixture' };
        if (!result.join_link) throw new Error("Calls API didn't return call link");
        const value = { joinLink: result.join_link, host: true };
        if (store) await store(value);
        writes.push(value);
        this.successHandler({ result: true, join_link: result.join_link });
      } catch (error) { this.errorHandler(error); }
    }
  }
  const original = CallStart.prototype.handler;
  function factory(module, exports) {
    Object.defineProperty(exports, 'VKWebAppCallStart', { enumerable: true, get: () => CallStart });
    exports.unrelated = 'preserved';
  }
  return { factory, CallStart, original, calls, writes };
}

async function flush() { for (let i = 0; i < 10; i++) await Promise.resolve(); }
function invoke(Klass, app, requestId = 'request-1') {
  const responses = [];
  new Klass().handler({ request_id: requestId }, app, value => responses.push(value));
  return responses;
}

test('mobile CallStart reaches the real provider path without changing isMVK, and waits for storage', async () => {
  const target = page();
  target.install();
  target.runtime();
  let finishStore;
  const module = officialModule(target, { store: () => new Promise(resolve => { finishStore = resolve; }) });
  const exports = target.publish(module.factory)();
  const responses = invoke(exports.VKWebAppCallStart, target.app, 'request-0');
  await flush();
  assert.equal(responses.length, 0);
  assert.deepEqual(module.calls, [{ method: 'apps.startCall', app_id: 123 }]);
  assert.equal(target.window.isMVK, true);
  finishStore();
  await flush();
  assert.deepEqual(responses, [{ type: 'VKWebAppCallStartResult', data: { result: true, join_link: 'real-provider-fixture', request_id: 'request-0' } }]);
  assert.equal(exports.unrelated, 'preserved');
  assert.equal(target.frame.listenerCount('load'), 0);
});

test('preserves the application switch, API failure and storage failure', async () => {
  for (const kind of ['disabled', 'api', 'storage', 'empty']) {
    const target = page(); target.install(); target.runtime();
    const module = officialModule(target, {
      api: async () => { if (kind === 'api') throw { code: 13, reason: 'Service denied' }; return { join_link: kind === 'empty' ? '' : 'link' }; },
      store: async () => { if (kind === 'storage') throw new Error('Storage failed'); }
    });
    if (kind === 'disabled') target.app.vkApp.options.is_calls_available = false;
    const responses = invoke(target.publish(module.factory)().VKWebAppCallStart, target.app);
    await flush();
    assert.equal(responses.length, 1);
    assert.equal(responses[0].type, 'VKWebAppCallStartFailed');
    assert.equal(responses[0].data.error_data.error_code, kind === 'disabled' ? 11 : kind === 'api' ? 13 : 1);
    assert.equal(module.calls.length, kind === 'disabled' ? 0 : 1);
    assert.equal(module.writes.length, 0);
  }
});

test('ignores non-VK pages, iframes and non-HTTPS pages', async () => {
  for (const options of [{ host: 'vk.ru.attacker.example' }, { top: false }, { protocol: 'http:' }]) {
    const target = page(options);
    if (options.protocol) target.sandbox.location.protocol = options.protocol;
    target.install(); target.runtime();
    const module = officialModule(target);
    const Klass = target.publish(module.factory)().VKWebAppCallStart;
    assert.equal(Klass.prototype.handler, module.original);
    assert.equal(invoke(Klass, target.app)[0].data.error_data.error_code, 6);
  }
});

test('preserves the desktop handler and refuses an unknown handler shape', async () => {
  const target = page({ host: 'vk.ru', mobile: false }); target.install(); target.runtime();
  const module = officialModule(target);
  const responses = invoke(target.publish(module.factory)().VKWebAppCallStart, target.app);
  await flush();
  assert.equal(responses[0].data.result, true);
  const changed = officialModule(target);
  changed.CallStart.prototype.handler = function() { return 'new-official-behavior'; };
  const original = changed.CallStart.prototype.handler;
  target.publish(changed.factory, 11)();
  assert.equal(changed.CallStart.prototype.handler, original);
});

test('handles queued modules, runtime push replacement, duplicate injection and different module ids', async () => {
  const target = page();
  const module = officialModule(target);
  target.publish(module.factory, 999, false);
  target.install(); target.install(); target.runtime();
  const exports = target.publish(function() {}, 888)();
  assert.deepEqual(exports, {});
  const getModule = target.publish(module.factory, 999);
  const Klass = getModule().VKWebAppCallStart;
  const firstPatched = Klass.prototype.handler;
  target.install();
  const responses = invoke(Klass, target.app);
  await flush();
  assert.equal(Klass.prototype.handler, firstPatched);
  assert.equal(responses[0].data.result, true);
  assert.equal(module.calls.length, 1);
});

test('drops delayed results after pagehide, iframe navigation or container replacement', async () => {
  for (const transition of ['pagehide', 'pageshow', 'load', 'src', 'removed', 'options', 'reInit']) {
    const target = page(); target.install(); target.runtime();
    let finish;
    const module = officialModule(target, { api: () => new Promise(resolve => { finish = resolve; }) });
    const responses = invoke(target.publish(module.factory)().VKWebAppCallStart, target.app);
    if (transition === 'pagehide') target.window.emit('pagehide');
    if (transition === 'pageshow') { target.window.emit('pagehide'); target.window.emit('pageshow'); }
    if (transition === 'load') target.frame.emit('load');
    if (transition === 'src') target.frame.src = 'https://other.example';
    if (transition === 'removed') target.frame.isConnected = false;
    if (transition === 'options') target.app.vkApp.options = { aid: 456, is_calls_available: true };
    if (transition === 'reInit') target.app.vkApp = { options: target.app.vkApp.options };
    finish({ join_link: 'late-result' });
    await flush();
    assert.equal(responses.length, 0, transition);
    assert.equal(target.frame.listenerCount('load'), 0, transition);
  }
});

test('keeps concurrent requests and same-app pages independent', async () => {
  const targets = [page(), page()];
  const pending = [];
  for (const target of targets) {
    target.install(); target.runtime();
    const module = officialModule(target, { api: () => new Promise(resolve => pending.push(resolve)) });
    const Klass = target.publish(module.factory)().VKWebAppCallStart;
    target.responses = [invoke(Klass, target.app, 'one'), invoke(Klass, target.app, 'two')];
  }
  targets[0].window.emit('pagehide');
  pending[3]({ join_link: 'fourth' }); pending[2]({ join_link: 'third' });
  pending[1]({ join_link: 'second' }); pending[0]({ join_link: 'first' });
  await flush();
  assert.deepEqual(targets[0].responses, [[], []]);
  assert.equal(targets[1].responses[0][0].data.request_id, 'one');
  assert.equal(targets[1].responses[0][0].data.join_link, 'third');
  assert.equal(targets[1].responses[1][0].data.request_id, 'two');
  assert.equal(targets[1].responses[1][0].data.join_link, 'fourth');
});
