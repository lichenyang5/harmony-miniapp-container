const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');
class PlatformURL extends URL { get params() { return this.searchParams; } }
const loadSDK = () => createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
  { '@kit.ArkTS': { url: { URL: PlatformURL } } });

class TestStorage {
  constructor(entries) {
    this.values = new Map(entries || []);
  }

  get length() {
    return this.values.size;
  }

  key(index) {
    return Array.from(this.values.keys())[index] ?? null;
  }

  getItem(key) {
    return this.values.has(key) ? this.values.get(key) : null;
  }

  setItem(key, value) {
    this.values.set(String(key), String(value));
  }

  removeItem(key) {
    this.values.delete(String(key));
  }
}

function runScript(script, localStorage, sessionStorage) {
  const windowObject = { localStorage, sessionStorage, Storage: TestStorage };
  vm.runInNewContext(script, { window: windowObject, console: { debug() {}, warn() {} } });
  return windowObject;
}

function context(type, extra) {
  return JSON.stringify(Object.assign({ type, liffId: '1657541296-Xk7G7gYK' }, extra));
}

test('context override normalizes existing and future LIFF contexts for any liffId', () => {
  const { createLineLiffContextOverrideScript } =
    loadSDK()('main/ets/vendors/line/script/LineLiffContextOverride');
  const script = createLineLiffContextOverrideScript('none').script;
  assert.match(script, /LIFF_STORE:\[\^:\]\+:context/);
  assert.equal(script.includes('1657541296'), false);

  const localStorage = new TestStorage([
    ['LIFF_STORE:1657541296-Xk7G7gYK:context',
      context('external', { endpointUrl: 'https://example.com/app', miniDomainAllowed: true })],
    ['LIFF_STORE:2012241484-PibjtMII:context', context('external', { liffId: '2012241484-PibjtMII' })],
    ['LIFF_STORE:1657541296-Xk7G7gYK:rawContext', 'raw-token'],
    ['OTHER:1657541296-Xk7G7gYK:context', context('external')]
  ]);
  const sessionStorage = new TestStorage([
    ['LIFF_STORE:1657541296-Xk7G7gYK:context', context('external')]
  ]);

  runScript(script, localStorage, sessionStorage);

  const first = JSON.parse(localStorage.getItem('LIFF_STORE:1657541296-Xk7G7gYK:context'));
  assert.equal(first.type, 'none');
  assert.equal(first.endpointUrl, 'https://example.com/app');
  assert.equal(first.miniDomainAllowed, true);
  assert.equal(JSON.parse(localStorage.getItem('LIFF_STORE:2012241484-PibjtMII:context')).type, 'none');
  assert.equal(JSON.parse(sessionStorage.getItem('LIFF_STORE:1657541296-Xk7G7gYK:context')).type, 'none');
  assert.equal(localStorage.getItem('LIFF_STORE:1657541296-Xk7G7gYK:rawContext'), 'raw-token');
  assert.equal(JSON.parse(localStorage.getItem('OTHER:1657541296-Xk7G7gYK:context')).type, 'external');

  localStorage.setItem('LIFF_STORE:999-abc:context', context('external', { scope: ['profile'] }));
  assert.deepEqual(JSON.parse(localStorage.getItem('LIFF_STORE:999-abc:context')),
    { type: 'none', liffId: '1657541296-Xk7G7gYK', scope: ['profile'] });
  localStorage.setItem('LIFF_STORE:999-abc:context', context('utou'));
  assert.equal(JSON.parse(localStorage.getItem('LIFF_STORE:999-abc:context')).type, 'utou');
  localStorage.setItem('LIFF_STORE:999-abc:context', 'not-json');
  assert.equal(localStorage.getItem('LIFF_STORE:999-abc:context'), 'not-json');
});

test('context override stays active when injected twice', () => {
  const { createLineLiffContextOverrideScript } =
    loadSDK()('main/ets/vendors/line/script/LineLiffContextOverride');
  const script = createLineLiffContextOverrideScript('none').script;
  const localStorage = new TestStorage();
  const sessionStorage = new TestStorage();

  runScript(script, localStorage, sessionStorage);
  runScript(script, localStorage, sessionStorage);
  localStorage.setItem('LIFF_STORE:any-id:context', context('external'));

  assert.equal(JSON.parse(localStorage.getItem('LIFF_STORE:any-id:context')).type, 'none');
});

function session(load, adapter, id = 'context') {
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  return new MiniAppSession(id, {
    info: { appId: '1657541296-Xk7G7gYK', vendor: 'line', url: 'https://miniapp.line.me/1657541296-Xk7G7gYK' },
    adapter, vendor: new LineVendor(), swipeBackController: { dispose() {} }
  }, {});
}

test('WEB and WEB_HOOK always install the context override', () => {
  const load = loadSDK();
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');

  const web = session(load, new LineAdapter({ mode: 'web' }));
  assert.equal(web.getAdapter().webContextType, 'none');
  const webScripts = web.getBinding().scripts;
  assert.equal(webScripts.length, 3);
  assert.equal(webScripts[0].required, true);
  assert.deepEqual(webScripts[0].scriptRules, ['*']);
  assert.match(webScripts[0].script, /LIFF_STORE:\[\^:\]\+:context/);
  assert.match(webScripts[0].script, /var overrideType = 'none';/);
  assert.doesNotMatch(webScripts.map(script => script.script).join(''), /\[LINE WebLogin\]/);

  const custom = session(load, new LineAdapter({ mode: 'web', webContextType: 'utou' }), 'custom');
  assert.match(custom.getBinding().scripts[0].script, /var overrideType = 'utou';/);

  const withLogin = session(load, new LineAdapter({ mode: 'web', forceLogin: true }), 'with-login');
  const withLoginScripts = withLogin.getBinding().scripts;
  assert.equal(withLoginScripts.length, 4);
  assert.match(withLoginScripts[1].script, /\[LINE WebLogin\]/);

  const hook = session(load, new LineAdapter({ mode: 'web_hook' }), 'hook');
  const hookScripts = hook.getBinding().scripts;
  assert.equal(hookScripts.length, 2);
  assert.match(hookScripts[0].script, /LIFF_STORE:\[\^:\]\+:context/);

  const hookLogin = session(load, new LineAdapter({ mode: 'web_hook', forceLogin: true }), 'hook-login');
  const hookLoginScripts = hookLogin.getBinding().scripts;
  assert.equal(hookLoginScripts.length, 3);
  assert.match(hookLoginScripts[1].script, /\[LINE WebLogin\]/);

  const client = session(load, new LineAdapter({ mode: 'client' }), 'client');
  assert.doesNotMatch(client.getBinding().scripts.map(script => script.script).join(''),
    /LIFF_STORE:\[\^:\]\+:context/);
});

function webLoginWindow(options) {
  const opts = options || {};
  const storage = new TestStorage(opts.entries);
  const timers = new Map();
  const timeouts = [];
  let nextId = 0;
  const win = {
    location: { protocol: 'https:', hostname: 'miniapp.line.me', search: opts.search || '' },
    sessionStorage: storage,
    top: undefined,
    liff: opts.liff,
    setInterval(callback) {
      timers.set(++nextId, callback);
      return nextId;
    },
    clearInterval(id) {
      timers.delete(id);
    },
    setTimeout(callback) {
      timeouts.push(callback);
    }
  };
  win.top = win;
  return { win, timers, timeouts };
}

function runLoginScript(script, win) {
  vm.runInNewContext(script, { window: win, console: { debug() {}, warn() {} } });
}

function tick(timers) {
  Array.from(timers.values()).forEach(callback => callback());
}

test('web login runs once after LIFF init and never for client or callback documents', () => {
  const { createLineLiffLoginScript } = loadSDK()('main/ets/vendors/line/script/LineLiffLogin');
  const script = createLineLiffLoginScript().script;
  assert.equal(script.includes('1657541296'), false);

  let loginCalls = 0;
  const pending = { getContext() { throw new Error('not initialized'); }, isLoggedIn: () => false, isInClient: () => false };
  const first = webLoginWindow({ liff: pending });
  runLoginScript(script, first.win);
  tick(first.timers);
  assert.equal(loginCalls, 0);

  pending.getContext = () => ({ type: 'none', liffId: '1657541296-Xk7G7gYK' });
  pending.login = () => { loginCalls += 1; };
  tick(first.timers);
  assert.equal(loginCalls, 1);
  assert.equal(first.win.sessionStorage.getItem('__atomicLineWebLoginAttempts'), '1');
  assert.equal(first.timers.size, 0);

  const loggedIn = webLoginWindow({
    entries: [['__atomicLineWebLoginAttempts', '1']],
    liff: { getContext: () => ({}), isLoggedIn: () => true, isInClient: () => false, login: () => { loginCalls += 1; } }
  });
  runLoginScript(script, loggedIn.win);
  tick(loggedIn.timers);
  assert.equal(loginCalls, 1);
  assert.equal(loggedIn.win.sessionStorage.getItem('__atomicLineWebLoginAttempts'), null);

  const client = webLoginWindow({
    liff: { getContext: () => ({}), isLoggedIn: () => false, isInClient: () => true, login: () => { loginCalls += 1; } }
  });
  runLoginScript(script, client.win);
  tick(client.timers);
  assert.equal(loginCalls, 1);

  const callback = webLoginWindow({ search: '?code=abc&state=def' });
  runLoginScript(script, callback.win);
  assert.equal(callback.timers.size, 0);

  const limited = webLoginWindow({
    entries: [['__atomicLineWebLoginAttempts', '2']],
    liff: { getContext: () => ({}), isLoggedIn: () => false, isInClient: () => false, login: () => { loginCalls += 1; } }
  });
  runLoginScript(script, limited.win);
  tick(limited.timers);
  assert.equal(loginCalls, 1);
  assert.equal(limited.timers.size, 0);
  assert.equal(limited.win.sessionStorage.getItem('__atomicLineWebLoginAttempts'), '2');
});
