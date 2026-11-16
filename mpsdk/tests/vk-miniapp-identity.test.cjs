const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const vendorRoot = path.resolve(__dirname, '../src/main/ets/vendors/vk');
function load(name) {
  const file = path.join(vendorRoot, name + '.ets');
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, { module, exports: module.exports, require, Set });
  return module.exports;
}

test('alias is resolved from the actual miniapp and recognizes mobile/desktop history', () => {
  const { VkMiniAppIdentity } = load('VkMiniAppIdentity');
  const identity = new VkMiniAppIdentity('https://vk.ru/pitprime_shop');
  assert.equal(identity.matches('https://vk.ru/pitprime_shop#B'), false);
  assert.equal(identity.identify('https://m.vk.ru/pitprime_shop', '123'), true);
  assert.equal(identity.matches('https://vk.ru/pitprime_shop#A'), true);
  assert.equal(identity.matches('https://vk.ru/pitprime_shop/persik'), true);
  assert.equal(identity.matches('https://m.vk.ru/app123?x=1#B'), true);
  assert.equal(identity.matches('https://m.vk.ru/app123/persik?x=1#B'), true);
  assert.equal(identity.matches('https://vk.com/app123/'), true);
  assert.equal(identity.matches('https://m.vk.ru/feed'), false);
  assert.equal(identity.matches('https://vk.ru/app456'), false);
  assert.equal(identity.matches('https://vk.ru.evil.example/pitprime_shop'), false);
  assert.equal(identity.identify('https://vk.ru/another_app', '456'), false);
});

test('alias redirect binds a canonical app, without trusting arbitrary VK routes', () => {
  const { VkMiniAppIdentity } = load('VkMiniAppIdentity');
  const identity = new VkMiniAppIdentity('https://vk.ru/pitprime_shop');
  assert.equal(identity.identify('https://m.vk.ru/feed', '123'), false);
  assert.equal(identity.identify('https://m.vk.ru/unrelated', '123'), false);
  assert.equal(identity.identify('https://m.vk.ru/app123', '123'), true);
  assert.equal(identity.matches('https://vk.ru/pitprime_shop'), true);
  assert.equal(identity.matches('https://m.vk.ru/app123'), true);
});

test('numeric entry keeps existing behavior and identity is isolated and disposable', () => {
  const { VkMiniAppIdentity } = load('VkMiniAppIdentity');
  const identity = new VkMiniAppIdentity('https://vk.ru/app123');
  assert.equal(identity.matches('https://m.vk.ru/app123#A'), true);
  assert.equal(identity.identify('https://vk.ru/app456', '456'), false);
  const other = new VkMiniAppIdentity('https://vk.ru/pitprime_shop');
  assert.equal(other.matches('https://vk.ru/app123'), false);
  identity.dispose();
  assert.equal(identity.matches('https://vk.ru/app123'), false);
  assert.equal(identity.identify('https://vk.ru/app123', '123'), false);
});

function loadIdentityScript() {
  const source = ts.createSourceFile('VkVendor.ets', fs.readFileSync(path.join(vendorRoot, 'VkVendor.ets'), 'utf8'), ts.ScriptTarget.Latest, true);
  const declaration = source.statements.find(node => ts.isFunctionDeclaration(node) && node.name?.text === 'createVkMiniAppIdentityScript');
  assert.ok(declaration, 'identity script generator exists in VkVendor');
  const code = ts.transpileModule(declaration.getText(source), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  return vm.runInNewContext(code + '\ncreateVkMiniAppIdentityScript;');
}

test('logged-in games redirect retains the exact numeric miniapp identity', () => {
  const { VkMiniAppIdentity } = load('VkMiniAppIdentity');
  for (const entry of ['https://m.vk.ru/app54793777', 'https://vk.ru/games/app54793777']) {
    const identity = new VkMiniAppIdentity(entry);
    assert.equal(identity.matches('https://m.vk.ru/games/app54793777'), true);
    assert.equal(identity.identify('https://m.vk.ru/games/app54793777', '54793777'), true);
    assert.equal(identity.matches('https://vk.ru/app54793777#/persik'), true);
    for (const address of ['https://m.vk.ru/games', 'https://m.vk.ru/games/catalog',
      'https://m.vk.ru/games/app54793778', 'https://m.vk.ru/games/app54793777fake',
      'https://m.vk.ru.evil.example/games/app54793777']) {
      assert.equal(identity.matches(address), false, address);
    }
  }
});

test('alias can identify a games redirect but cannot bind a second app', () => {
  const { VkMiniAppIdentity } = load('VkMiniAppIdentity');
  const identity = new VkMiniAppIdentity('https://vk.ru/pitprime_shop');
  assert.equal(identity.identify('https://m.vk.ru/games/app54793777', '54793777'), true);
  assert.equal(identity.matches('https://vk.ru/pitprime_shop'), true);
  assert.equal(identity.identify('https://m.vk.ru/games/app54793778', '54793778'), false);
});

function browser(entry, href, frames = []) {
  const createVkMiniAppIdentityScript = loadIdentityScript();
  const reports = [], callbacks = [], listeners = {}, intervals = [], redirects = [], storage = new Map(), headers = [];
  let hostBackCalls = 0;
  const localStorage = { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key) };
  const ctx = { URL, location: new URL(href), document: { querySelectorAll: selector => selector === 'iframe' ? frames : headers },
    localStorage, sessionStorage: localStorage,
    setInterval(cb) { intervals.push(cb); return intervals.length; }, clearInterval() {},
    setTimeout(cb) { cb(); },
    HosBridge: {
      onMiniAppIdentified: (...args) => { reports.push(args); return true; },
      onHostGoBack: () => { hostBackCalls++; }
    },
    MutationObserver: class { constructor(cb) { callbacks.push(cb); } observe() {} disconnect() {} },
    addEventListener: (name, cb) => { (listeners[name] ||= []).push(cb); },
    console: { info() {}, log() {}, warn() {}, error() {} } };
  ctx.window = ctx; ctx.top = ctx;
  ctx.location.replace = address => redirects.push(address);
  vm.createContext(ctx);
  vm.runInContext(createVkMiniAppIdentityScript(entry), ctx);
  return { ctx, reports, listeners, hostBackCalls: () => hostBackCalls,
    scan: () => ctx.__vkMiniAppIdentity.scan(), frames, redirects, storage, headers,
    tick: () => intervals.forEach(cb => cb()),
    pump: () => { callbacks.forEach(cb => cb()); intervals.forEach(cb => cb()); } };
}
function miniFrame(id = '123') {
  return { src: `https://mini.example/?vk_app_id=${id}&vk_user_id=7&sign=test`,
    getAttribute() { return this.src; } };
}

test('login redirect to games enables host patches only for the matching launch iframe', () => {
  const f = browser('https://m.vk.ru/app54793777', 'https://m.vk.ru/games/app54793777',
    [miniFrame('54793777')]);
  assert.equal(f.ctx.__vkMiniAppIdentity.hasMiniApp(), true);
  assert.deepEqual(f.reports, [['https://m.vk.ru/games/app54793777', '54793777']]);
  f.ctx.Apps = { goBack() { throw new Error('must not call VK back'); } };
  runVendorScript('vkHostPatchScript', f.ctx);
  f.ctx.Apps.goBack();
  assert.equal(f.hostBackCalls(), 1);
  const other = browser('https://m.vk.ru/app54793777', 'https://m.vk.ru/games/app54793778',
    [miniFrame('54793778')]);
  assert.equal(other.ctx.__vkMiniAppIdentity.isTargetApp(), false);
  assert.equal(other.reports.length, 0);
  const lobby = browser('https://vk.ru/games', 'https://m.vk.ru/games/app54793777',
    [miniFrame('54793777')]);
  assert.equal(lobby.ctx.__vkMiniAppIdentity.isTargetApp(), false);
});

test('document-start detection recognizes configured alias, but not feed or lookalike hosts', () => {
  const f = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/pitprime_shop#route');
  assert.equal(f.ctx.__vkMiniAppIdentity.isTargetApp(), true);
  assert.equal(f.reports.length, 0);
  f.frames.push(miniFrame()); f.scan(); f.scan();
  assert.equal(f.reports.length, 1);
  assert.deepEqual(f.reports[0], ['https://m.vk.ru/pitprime_shop#route', '123']);
  assert.equal(browser('https://vk.ru/pitprime_shop', 'https://vk.ru/feed').ctx.__vkMiniAppIdentity.isTargetApp(), false);
  assert.equal(browser('https://vk.ru/pitprime_shop', 'https://vk.ru.evil.example/pitprime_shop').ctx.__vkMiniAppIdentity, undefined);
});

test('document-start detection keeps alias identity on an internal location path', () => {
  const f = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/pitprime_shop/persik', [miniFrame()]);
  assert.equal(f.ctx.__vkMiniAppIdentity.isTargetApp(), true);
  assert.equal(f.reports.length, 1);
  assert.deepEqual(f.reports[0], ['https://m.vk.ru/pitprime_shop/persik', '123']);
});

test('canonical redirect waits for a matching launch iframe, and rejects ambiguous frames', () => {
  const f = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/app123');
  assert.equal(f.ctx.__vkMiniAppIdentity.isTargetApp(), false);
  f.frames.push(miniFrame()); f.scan();
  assert.equal(f.ctx.__vkMiniAppIdentity.isTargetApp(), true);
  assert.equal(f.reports.length, 1);
  const g = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/app123', [miniFrame(), miniFrame('456')]);
  assert.equal(g.reports.length, 0);
  assert.equal(g.ctx.__vkMiniAppIdentity.isTargetApp(), false);
});

test('native rejection of a different app is respected by the host script', () => {
  const f = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/app456');
  f.ctx.HosBridge.onMiniAppIdentified = () => false;
  f.frames.push(miniFrame('456'));
  assert.equal(f.ctx.__vkMiniAppIdentity.hasMiniApp(), false);
  assert.equal(f.ctx.__vkMiniAppIdentity.isTargetApp(), false);
});

function runVendorScript(name, ctx) {
  const source = ts.createSourceFile('VkVendor.ets', fs.readFileSync(path.join(vendorRoot, 'VkVendor.ets'), 'utf8'), ts.ScriptTarget.Latest, true);
  const declaration = source.statements.filter(ts.isVariableStatement)
    .flatMap(s => [...s.declarationList.declarations]).find(d => d.name.getText(source) === name);
  assert.ok(declaration, 'script exists: ' + name);
  const script = Function('BuildProfile', 'return ' + declaration.initializer.getText(source))({ DEBUG: false });
  vm.runInContext(script, ctx);
}

test('alias login saves the exact target, returns from feed, and does not force cross-origin desktop login', () => {
  const f = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/pitprime_shop?start=1');
  runVendorScript('loginScript', f.ctx);
  assert.deepEqual(f.redirects, ['https://m.vk.ru/']);
  assert.equal(f.storage.get('vk_app_pending'), 'https://m.vk.ru/pitprime_shop?start=1');
  f.ctx.location.href = 'https://m.vk.ru/feed';
  runVendorScript('loginScript', f.ctx);
  assert.equal(f.redirects[1], 'https://m.vk.ru/pitprime_shop?start=1');
  const g = browser('https://vk.ru/pitprime_shop', 'https://vk.ru/pitprime_shop');
  runVendorScript('loginScript', g.ctx);
  assert.equal(g.redirects.length, 0);
});

test('host patch activates for a delayed canonical iframe, while feed stays untouched', () => {
  const f = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/app123');
  let calls = 0, removed = 0;
  const goBack = () => calls++;
  f.ctx.Apps = { goBack };
  f.headers.push({ parentNode: { removeChild: () => removed++ } });
  runVendorScript('vkHostPatchScript', f.ctx);
  assert.equal(f.ctx.Apps.goBack, goBack); assert.equal(removed, 0);
  f.frames.push(miniFrame()); f.pump();
  assert.notEqual(f.ctx.Apps.goBack, goBack); assert.equal(removed, 0);
  f.ctx.Apps.goBack(); assert.equal(calls, 0); assert.equal(f.hostBackCalls(), 1); assert.equal(f.reports.length, 1);
  const g = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/feed');
  g.ctx.Apps = { goBack }; runVendorScript('vkHostPatchScript', g.ctx); g.pump();
  assert.equal(g.ctx.Apps.goBack, goBack);
});

test('host goBack hook never falls back to the original VK method when the native bridge fails', () => {
  const f = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/app123', [miniFrame()]);
  let originalCalls = 0;
  f.ctx.Apps = { goBack: () => originalCalls++ };
  f.ctx.HosBridge.onHostGoBack = () => { throw new Error('native bridge unavailable'); };
  runVendorScript('vkHostPatchScript', f.ctx);

  f.ctx.Apps.goBack();

  assert.equal(originalCalls, 0);
  assert.notEqual(f.ctx.Apps.goBack, undefined);
});

test('nav tab-history back uses native safe return without calling VK navigation', () => {
  const f = browser('https://vk.ru/pitprime_shop', 'https://vk.ru/pitprime_shop', [miniFrame()]);
  let calls = 0;
  const original = function (element, options) {
    calls++;
    assert.equal(this, f.ctx.nav);
    return options.href;
  };
  f.ctx.nav = { backToTabHistory: original, go() {} };
  const go = f.ctx.nav.go;
  runVendorScript('vkHostPatchScript', f.ctx);
  f.tick();
  assert.notEqual(f.ctx.nav.backToTabHistory, original);
  assert.equal(f.ctx.nav.backToTabHistory({ href: '/apps' }, { href: '/feed', replace: true }), false);
  assert.equal(calls, 0);
  assert.equal(f.hostBackCalls(), 1);
  f.ctx.HosBridge.onHostGoBack = () => { throw new Error('native unavailable'); };
  assert.equal(f.ctx.nav.backToTabHistory(), false);
  delete f.ctx.HosBridge;
  assert.equal(f.ctx.nav.backToTabHistory(), false);
  assert.equal(calls, 0, 'native failures must not fall back to VK');
  assert.equal(f.ctx.nav.go, go, 'forward navigation is unchanged');
});

test('late or replaced nav methods are hooked while non-miniapp pages retain VK behavior', () => {
  const f = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/app123', [miniFrame()]);
  runVendorScript('vkHostPatchScript', f.ctx);
  let originalCalls = 0;
  const original = function (...args) { originalCalls++; assert.equal(this, f.ctx.nav); return args[0]; };
  f.ctx.nav = { backToTabHistory: original };
  f.tick();
  runVendorScript('vkHostPatchScript', f.ctx);
  f.ctx.nav.backToTabHistory();
  assert.equal(f.hostBackCalls(), 1);
  assert.equal(originalCalls, 0);
  f.ctx.nav.backToTabHistory = original;
  f.tick();
  f.ctx.nav.backToTabHistory();
  assert.equal(f.hostBackCalls(), 2);
  assert.equal(originalCalls, 0);
  f.ctx.location.href = 'https://m.vk.ru/login';
  f.frames.length = 0;
  assert.equal(f.ctx.nav.backToTabHistory('login-back'), 'login-back');
  assert.equal(originalCalls, 1);
  const login = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/login');
  login.ctx.nav = { backToTabHistory: original };
  runVendorScript('vkHostPatchScript', login.ctx);
  assert.equal(login.ctx.nav.backToTabHistory, original);
});

test('nav tab-history anchor default is cancelled without submitting duplicate back', () => {
  const f = browser('https://vk.ru/pitprime_shop', 'https://vk.ru/pitprime_shop');
  let calls = 0;
  f.ctx.nav = { backToTabHistory() { calls++; } };
  runVendorScript('vkHostPatchScript', f.ctx);
  const link = { getAttribute: () => 'nav.backToTabHistory(this, {replace: true})' };
  const event = { target: { closest: () => link }, prevented: false,
    preventDefault() { this.prevented = true; } };
  for (const listener of f.listeners.click || []) listener(event);
  assert.equal(event.prevented, true);
  assert.equal(f.hostBackCalls(), 0);
  f.ctx.nav.backToTabHistory(link);
  assert.equal(f.hostBackCalls(), 1);
  assert.equal(calls, 0);
  link.getAttribute = () => 'nav.go(this.href)';
  event.prevented = false;
  for (const listener of f.listeners.click || []) listener(event);
  assert.equal(event.prevented, false);
});

function headerClick({ header = true, close = true, label = '', nested = false } = {}) {
  const button = {
    closest(selector) {
      if (selector === 'a.vkAppHeader__back') return this;
      if (selector === 'div[class*="vkAppHeader"]') return header ? {} : null;
      return null;
    },
    querySelector: () => close ? {} : null,
    getAttribute: () => label
  };
  return { type: 'click', currentTarget: nested ? null : button,
    target: { closest: () => button }, defaultPrevented: false,
    preventDefault() { this.defaultPrevented = true; } };
}

test('header close clicks route directly to native close and cancel the anchor navigation', () => {
  for (const options of [{}, { nested: true }, { close: false, label: '关闭' }]) {
    const f = browser('https://vk.ru/pitprime_shop', 'https://vk.ru/pitprime_shop');
    let closes = 0;
    f.ctx.HosBridge.onHostClose = () => closes++;
    f.ctx.Apps = { goBack() { assert.fail('must not call VK'); } };
    runVendorScript('vkHostPatchScript', f.ctx);
    const event = headerClick(options);
    f.ctx.Apps.goBack(event, true, null, null);
    assert.equal(closes, 1);
    assert.equal(f.hostBackCalls(), 0);
    assert.equal(event.defaultPrevented, true);
  }
});

test('ordinary back buttons and programmatic calls keep the existing safe back path', () => {
  const f = browser('https://vk.ru/pitprime_shop', 'https://vk.ru/pitprime_shop');
  f.ctx.HosBridge.onHostClose = () => assert.fail('must not close');
  f.ctx.Apps = { goBack() {} };
  runVendorScript('vkHostPatchScript', f.ctx);
  for (const event of [headerClick({ header: false }), headerClick({ close: false, label: '返回' })]) {
    f.ctx.Apps.goBack(event, true);
    assert.equal(event.defaultPrevented, true);
  }
  f.ctx.Apps.goBack();
  assert.equal(f.hostBackCalls(), 3);
});

test('missing or throwing native close never falls back to history or the anchor href', () => {
  for (const close of [undefined, () => { throw new Error('unavailable'); }]) {
    const f = browser('https://vk.ru/pitprime_shop', 'https://vk.ru/pitprime_shop');
    f.ctx.HosBridge.onHostClose = close;
    f.ctx.Apps = { goBack() { assert.fail('must not call VK'); } };
    runVendorScript('vkHostPatchScript', f.ctx);
    const event = headerClick();
    assert.doesNotThrow(() => f.ctx.Apps.goBack(event));
    assert.equal(event.defaultPrevented, true);
    assert.equal(f.hostBackCalls(), 0);
  }
});

test('host patch hooks goBack without removing the header when an existing iframe gets its src later', () => {
  const frame = miniFrame(); const launchUrl = frame.src; frame.src = 'about:blank';
  const f = browser('https://vk.ru/pitprime_shop', 'https://m.vk.ru/app123', [frame]);
  let removed = 0;
  const goBack = () => {};
  f.ctx.Apps = { goBack };
  f.headers.push({ parentNode: { removeChild: () => removed++ } });
  runVendorScript('vkHostPatchScript', f.ctx);
  assert.equal(removed, 0);
  assert.equal(f.ctx.Apps.goBack, goBack);
  frame.src = launchUrl; f.tick(); // No child-list mutation.
  assert.equal(removed, 0);
  assert.notEqual(f.ctx.Apps.goBack, goBack);
  f.ctx.Apps.goBack();
  assert.equal(f.hostBackCalls(), 1);
});
