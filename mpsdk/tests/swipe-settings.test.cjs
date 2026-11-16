// Run with TYPESCRIPT_PATH pointing to the local TypeScript installation.
// Only platform dependencies are replaced; session, navigation and handler use real sources.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');

const sourceRoot = path.resolve(__dirname, '../src/main/ets');
const cache = new Map();
const platform = { sdkApiVersion: 18, circle: false };
function load(filename) {
  filename = path.resolve(filename);
  if (cache.has(filename)) return cache.get(filename).exports;
  const module = { exports: {} };
  cache.set(filename, module);
  const source = fs.readFileSync(filename, 'utf8');
  const compiled = ts.transpileModule(source, {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: {
      target: ts.ScriptTarget.ES2021,
      module: ts.ModuleKind.CommonJS,
      experimentalDecorators: true,
    },
  }).outputText;
  const localRequire = (name) => {
    if (name === '@kit.BasicServicesKit') return { deviceInfo: platform };
    if (name.endsWith('/BuildProfile')) return { default: { DEBUG: false } };
    if (!name.startsWith('.')) throw new Error(`Unexpected platform dependency: ${name}`);
    const target = path.resolve(path.dirname(filename), name);
    const resolved = [target, `${target}.ets`, `${target}.ts`].find((file) => fs.existsSync(file));
    if (!resolved) throw new Error(`Cannot resolve ${name} from ${filename}`);
    return load(resolved);
  };
  const run = vm.runInThisContext(`(function(require, module, exports, canIUse) {${compiled}\n})`, { filename });
  run(localRequire, module, module.exports, (capability) => {
    assert.equal(capability, 'SystemCapability.ArkUI.ArkUI.Circle');
    return platform.circle;
  });
  return module.exports;
}

const { MiniAppSession } = load(path.join(sourceRoot, 'core/Runtime.ets'));
const { MiniAppAdapter } = load(path.join(sourceRoot, 'core/MiniAppAdapter.ets'));
const { MiniAppNavigationController } = load(path.join(sourceRoot, 'web/MiniAppNavigationController.ets'));
const { VkSwipeSettingsHandler } = load(path.join(sourceRoot, 'vendors/vk/handlers/VkSwipeSettingsHandler.ets'));
const { VkNavigationController } = load(path.join(sourceRoot, 'vendors/vk/VkNavigationController.ets'));
const { VkMiniAppIdentity } = load(path.join(sourceRoot, 'vendors/vk/VkMiniAppIdentity.ets'));

function fixture(options = {}) {
  let nativeCalls = 0;
  let closeCalls = 0;
  const nativeSettings = [];
  const adapter = new MiniAppAdapter({});
  const swipeBackController = adapter.createSwipeBackController({
    enableSwipeBack(enabled) { nativeCalls++; nativeSettings.push(enabled); },
  });
  const vendor = {
    vendorId: 'swipe-test',
    createBinding() { return { miniAppIdentity: options.miniAppIdentity, onDocumentChanged() {}, dispose() {} }; },
  };
  const session = new MiniAppSession('test', {
    info: { appId: 'same-app', vendor: 'swipe-test', url: options.url || 'https://example.com' },
    vendor, adapter, swipeBackController,
    onClose: options.onClose || (() => closeCalls++),
  }, {});
  const navigation = options.navigation || new MiniAppNavigationController();
  const endpoint = { session, controller: options.controller, goHome() {}, refresh() {} };
  navigation.attach(endpoint);
  return { session, navigation, endpoint, handler: new VkSwipeSettingsHandler(session), nativeCalls: () => nativeCalls,
    nativeSettings, closeCalls: () => closeCalls };
}

test('host back handling consumes false, releases true, and does not call the Circle API', async (t) => {
  const f = fixture();
  t.after(() => f.session.close());
  f.navigation.enableBackPressHandling();
  assert.equal(f.navigation.handleBackPress(), false);
  assert.deepEqual(await f.handler.setSwipeSettings({ history: false }), { result: true });
  assert.equal(f.navigation.handleBackPress(), true);
  assert.deepEqual(await f.handler.setSwipeSettings({ history: true }), { result: true });
  assert.equal(f.navigation.handleBackPress(), false);
  assert.equal(f.nativeCalls(), 0);
});

test('missing host integration on a non-Circle device reports unsupported', async (t) => {
  const f = fixture();
  t.after(() => f.session.close());
  await assert.rejects(f.handler.setSwipeSettings({ history: false }), (error) => {
    assert.equal(error.toData().error_data.error_code, 6);
    return true;
  });
  assert.equal(f.nativeCalls(), 0);
});

test('closed sessions and detached navigation do not trap the user', async (t) => {
  const f = fixture();
  t.after(() => f.session.close());
  f.navigation.enableBackPressHandling();
  await f.handler.setSwipeSettings({ history: false });
  f.navigation.detach(f.endpoint);
  assert.equal(f.navigation.handleBackPress(), false);
  f.navigation.attach(f.endpoint);
  assert.equal(f.navigation.handleBackPress(), true);
  f.session.close();
  assert.equal(f.navigation.handleBackPress(), false);
  assert.throws(() => f.session.setSwipeBackEnabled(false), { code: 'SESSION_CLOSED' });
});

test('new top-level documents reset the host policy', async (t) => {
  const f = fixture();
  t.after(() => f.session.close());
  f.navigation.enableBackPressHandling();
  await f.handler.setSwipeSettings({ history: false });
  f.session.beginDocument('https://example.com/next');
  assert.equal(f.navigation.handleBackPress(), false);
  await f.handler.setSwipeSettings({ history: false });
  assert.equal(f.navigation.handleBackPress(), true);
});

test('sessions sharing an app id keep independent host policies', async (t) => {
  const first = fixture();
  const second = fixture();
  t.after(() => { first.session.close(); second.session.close(); });
  first.navigation.enableBackPressHandling();
  second.navigation.enableBackPressHandling();
  await first.handler.setSwipeSettings({ history: false });
  assert.equal(first.navigation.handleBackPress(), true);
  assert.equal(second.navigation.handleBackPress(), false);
  second.session.close();
  assert.equal(first.navigation.handleBackPress(), true);
});

test('invalid arguments cannot replace a valid policy', async (t) => {
  const f = fixture();
  t.after(() => f.session.close());
  f.navigation.enableBackPressHandling();
  await f.handler.setSwipeSettings({ history: false });
  await assert.rejects(f.handler.setSwipeSettings({}), { code: 'MISSING_REQUIRED_PARAMS' });
  assert.equal(f.navigation.handleBackPress(), true);
  for (const params of [{ history: 'true' }, { history: null }, []]) {
    await assert.rejects(f.handler.setSwipeSettings(params), { code: 'INVALID_ARGUMENT' });
    assert.equal(f.navigation.handleBackPress(), true);
  }
});

test('unbound navigation leaves default back behavior unchanged', () => {
  const navigation = new MiniAppNavigationController();
  navigation.enableBackPressHandling();
  assert.equal(navigation.handleBackPress(), false);
});

test('old views cannot detach a newer host navigation handler', (t) => {
  const f = fixture();
  t.after(() => f.session.close());
  let firstCalls = 0, secondCalls = 0;
  const first = { handleHostGoBack() { firstCalls++; } };
  const second = { handleHostGoBack() { secondCalls++; } };

  f.session.attachHostNavigation(first);
  f.session.attachHostNavigation(second);
  f.session.detachHostNavigation(first);
  f.session.handleHostGoBack();

  assert.equal(firstCalls, 0);
  assert.equal(secondCalls, 1);
});

test('host back handling works below API 18 without invoking the native API', async (t) => {
  platform.sdkApiVersion = 15;
  const f = fixture();
  t.after(() => { f.session.close(); platform.sdkApiVersion = 18; });
  f.navigation.enableBackPressHandling();
  await f.handler.setSwipeSettings({ history: false });
  assert.equal(f.navigation.handleBackPress(), true);
  await f.handler.setSwipeSettings({ history: true });
  assert.equal(f.navigation.handleBackPress(), false);
  assert.equal(f.nativeCalls(), 0);
});

test('Circle fallback applies native settings and restores the default on close', async (t) => {
  platform.circle = true;
  const f = fixture();
  t.after(() => { f.session.close(); platform.circle = false; });
  await f.handler.setSwipeSettings({ history: false });
  await f.handler.setSwipeSettings({ history: true });
  await f.handler.setSwipeSettings({ history: false });
  assert.deepEqual(f.nativeSettings, [false, true, false]);
  assert.equal(f.navigation.handleBackPress(), false);
  f.session.close();
  assert.deepEqual(f.nativeSettings, [false, true, false, true]);
});

test('Circle fallback below API 18 remains unsupported', async (t) => {
  platform.circle = true;
  platform.sdkApiVersion = 17;
  const f = fixture();
  t.after(() => { f.session.close(); platform.circle = false; platform.sdkApiVersion = 18; });
  await assert.rejects(f.handler.setSwipeSettings({ history: false }), (error) => {
    assert.equal(error.toData().error_data.error_code, 6);
    return true;
  });
  assert.equal(f.nativeCalls(), 0);
});

const vkAppUrl = 'https://m.vk.ru/app54769936';
function vkHistoryFixture(t, urls, currentIndex = urls.length - 1, entryUrl = 'https://vk.ru/app54769936',
  exposeIdentity = true) {
  const state = { currentIndex, backwardCalls: 0, pending: false, failRead: false, failBack: false };
  const controller = {
    getBackForwardEntries() {
      if (state.failRead) throw new Error('history unavailable');
      return {
        currentIndex: state.currentIndex,
        size: urls.length,
        getItemAtIndex(index) {
          assert.ok(index >= 0 && index < urls.length);
          return { historyUrl: urls[index], historyRawUrl: urls[index], title: '', icon: null };
        },
      };
    },
    backward() {
      if (state.failBack) throw new Error('navigation failed');
      state.backwardCalls++;
      if (!state.pending) state.currentIndex--;
    },
  };
  const identity = new VkMiniAppIdentity(entryUrl);
  const f = fixture({ navigation: new VkNavigationController(), controller, url: entryUrl,
    miniAppIdentity: exposeIdentity ? identity : undefined });
  f.navigation.enableBackPressHandling();
  f.session.attachHostNavigation(f.navigation);
  t.after(() => f.session.close());
  return { ...f, state, identity };
}

test('VK swipe back keeps the initial-url identity fallback while binding identity is not ready', (t) => {
  const f = vkHistoryFixture(t, [vkAppUrl + '#A', vkAppUrl + '#B'], 1, vkAppUrl, false);

  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.currentIndex, 0);
  assert.equal(f.state.backwardCalls, 1);
});

test('VK swipe back recognizes VKWebAppSetLocation paths below an alias entry', (t) => {
  const entry = 'https://vk.ru/pitprime_shop';
  const f = vkHistoryFixture(t, [entry, entry + '/persik'], 1, entry);
  assert.equal(f.identity.identify(entry, '54769936'), true);

  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.currentIndex, 0);
  assert.equal(f.state.backwardCalls, 1);
});

test('back after login to games/app keeps B to A inside the same app', async (t) => {
  const entry = 'https://m.vk.ru/app54793777';
  const games = 'https://m.vk.ru/games/app54793777';
  const f = vkHistoryFixture(t, ['https://m.vk.ru/feed', games, games + '#/persik'], 2, entry);
  await f.handler.setSwipeSettings({ history: false });
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.backwardCalls, 0);
  await f.handler.setSwipeSettings({ history: true });
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.currentIndex, 1);
  assert.equal(f.state.backwardCalls, 1);
  f.session.handleHostGoBack();
  assert.equal(f.closeCalls(), 1);
  assert.equal(f.state.backwardCalls, 1);
});

test('games navigation never backs into lobby or another game', (t) => {
  for (const previous of ['https://m.vk.ru/games', 'https://m.vk.ru/games/app54793778']) {
    const f = vkHistoryFixture(t, [previous, 'https://m.vk.ru/games/app54793777'], 1,
      'https://m.vk.ru/app54793777');
    f.session.handleHostGoBack();
    assert.equal(f.closeCalls(), 1);
    assert.equal(f.state.backwardCalls, 0);
  }
});

test('Apps goBack returns from B to A even when swipe history is disabled', async (t) => {
  const entry = 'https://vk.ru/pitprime_shop';
  const f = vkHistoryFixture(t, [entry + '#home', vkAppUrl + '#A', vkAppUrl + '#B'], 2, entry);
  assert.equal(f.identity.identify(vkAppUrl, '54769936'), true);
  await f.handler.setSwipeSettings({ history: false });

  f.session.handleHostGoBack();

  assert.equal(f.state.currentIndex, 1);
  assert.equal(f.state.backwardCalls, 1);
  assert.equal(f.closeCalls(), 0);
  assert.equal(f.navigation.handleBackPress(), true, 'swipe policy remains disabled');
});

test('Apps goBack closes the container at miniapp history boundary', (t) => {
  const entry = 'https://vk.ru/pitprime_shop';
  const f = vkHistoryFixture(t, ['https://id.vk.com/auth', entry], 1, entry);
  assert.equal(f.identity.identify('https://m.vk.ru/app54769936', '54769936'), true);

  f.session.handleHostGoBack();

  assert.equal(f.state.backwardCalls, 0);
  assert.equal(f.closeCalls(), 1);
  assert.throws(() => f.session.getBinding(), { code: 'SESSION_CLOSED' });
});

test('Apps goBack consumes unknown history without navigating or closing', (t) => {
  const unconfirmed = vkHistoryFixture(t, ['https://m.vk.ru/feed', 'https://vk.ru/pitprime_shop'], 1,
    'https://vk.ru/pitprime_shop');
  unconfirmed.session.handleHostGoBack();
  assert.equal(unconfirmed.state.backwardCalls, 0);
  assert.equal(unconfirmed.closeCalls(), 0);

  const failed = vkHistoryFixture(t, [vkAppUrl, vkAppUrl]);
  failed.state.failRead = true;
  failed.session.handleHostGoBack();
  assert.equal(failed.state.backwardCalls, 0);
  assert.equal(failed.closeCalls(), 0);

  const backFailed = vkHistoryFixture(t, [vkAppUrl, vkAppUrl]);
  backFailed.state.failBack = true;
  backFailed.session.handleHostGoBack();
  assert.equal(backFailed.state.backwardCalls, 0);
  assert.equal(backFailed.closeCalls(), 0);
});

test('immediate repeated Apps goBack calls share the pending miniapp back', (t) => {
  const f = vkHistoryFixture(t, [vkAppUrl, vkAppUrl, vkAppUrl]);
  f.state.pending = true;

  f.session.handleHostGoBack();
  f.session.handleHostGoBack();

  assert.equal(f.state.backwardCalls, 1);
  assert.equal(f.closeCalls(), 0);
});

test('observed alias miniapp goes back across alias/canonical records and still respects swipe disabling', async (t) => {
  const entry = 'https://vk.ru/pitprime_shop';
  const f = vkHistoryFixture(t, ['https://m.vk.ru/feed', entry + '#home', vkAppUrl + '#A', vkAppUrl + '#B'], 3, entry);
  assert.equal(f.identity.identify(vkAppUrl, '54769936'), true);
  await f.handler.setSwipeSettings({ history: false });
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.backwardCalls, 0);
  await f.handler.setSwipeSettings({ history: true });
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.currentIndex, 2);
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.currentIndex, 1);
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.closeCalls(), 1);
  assert.equal(f.state.backwardCalls, 2);
});

test('VK enabled swipe goes back one joint-history entry before closing through the session', async (t) => {
  const f = vkHistoryFixture(t, ['https://id.vk.com/auth', vkAppUrl, vkAppUrl]);
  await f.handler.setSwipeSettings({ history: true });
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.currentIndex, 1);
  assert.equal(f.state.backwardCalls, 1);
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.closeCalls(), 1);
  assert.equal(f.state.backwardCalls, 1);
});

test('VK disabled swipe neither navigates nor exits; re-enabling restores page back', async (t) => {
  const f = vkHistoryFixture(t, [vkAppUrl, vkAppUrl]);
  await f.handler.setSwipeSettings({ history: false });
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.backwardCalls, 0);
  await f.handler.setSwipeSettings({ history: true });
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.currentIndex, 0);
});

test('VK back never traverses a login, another miniapp or a lookalike domain', (t) => {
  for (const previous of [
    'https://id.vk.com/auth', 'https://m.vk.ru/feed', 'https://m.vk.ru/app123',
    'https://vk.ru.evil.example/app54769936', 'https://m.vk.ru/app547699360',
  ]) {
    const f = vkHistoryFixture(t, [previous, vkAppUrl]);
    assert.equal(f.navigation.handleBackPress(), true);
    assert.equal(f.closeCalls(), 1);
    assert.equal(f.state.backwardCalls, 0);
  }
});

test('all VK back entries consume unconfirmed history without exiting', (t) => {
  const entry = 'https://vk.ru/pitprime_shop';
  const f = vkHistoryFixture(t, ['https://m.vk.ru/feed', entry], 1, entry);
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.navigation.goBack(), true);
  f.session.handleHostGoBack();
  assert.equal(f.closeCalls(), 0);
  assert.equal(f.state.backwardCalls, 0);
});

test('toolbar, page button and system back share one pending return', (t) => {
  const f = vkHistoryFixture(t, [vkAppUrl, vkAppUrl + '#A', vkAppUrl + '#B']);
  f.state.pending = true;
  assert.equal(f.navigation.goBack(), true);
  f.session.handleHostGoBack();
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.backwardCalls, 1);
  assert.equal(f.closeCalls(), 0);
});

test('explicit toolbar back ignores swipe disabling and closes at root only once', async (t) => {
  const f = vkHistoryFixture(t, [vkAppUrl]);
  await f.handler.setSwipeSettings({ history: false });
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.closeCalls(), 0);
  assert.equal(f.navigation.goBack(), true);
  f.navigation.handleHostGoBack();
  assert.equal(f.closeCalls(), 1);
  assert.equal(f.state.backwardCalls, 0);
  assert.equal(f.navigation.handleBackPress(), false, 'closed session no longer owns system back');
});

test('close failure consumes system back without navigating into VK', (t) => {
  const f = vkHistoryFixture(t, [vkAppUrl]);
  f.session.requestClose = () => { throw new Error('close unavailable'); };
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.closeCalls(), 0);
  assert.equal(f.state.backwardCalls, 0);
});

test('VK history recognizes official mobile/desktop domains and route fragments', (t) => {
  const f = vkHistoryFixture(t, ['https://vk.com/app54769936?x=1#/', `${vkAppUrl}#/persik`]);
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.currentIndex, 0);
});

test('history lookup or back failure consumes the gesture instead of accidentally exiting', (t) => {
  const f = vkHistoryFixture(t, [vkAppUrl, vkAppUrl]);
  f.state.failRead = true;
  assert.equal(f.navigation.handleBackPress(), true);
  f.state.failRead = false;
  f.state.failBack = true;
  assert.equal(f.navigation.handleBackPress(), true);
  f.state.failBack = false;
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.backwardCalls, 1);
});

test('immediate repeated swipes are coalesced while the history index is unchanged', (t) => {
  const f = vkHistoryFixture(t, [vkAppUrl, vkAppUrl, vkAppUrl]);
  f.state.pending = true;
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.backwardCalls, 1);
  f.state.currentIndex = 1;
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.backwardCalls, 2);
});

test('an unchanged history can be retried after the short coalescing window', (t) => {
  let now = Date.now();
  t.mock.method(Date, 'now', () => now);
  const f = vkHistoryFixture(t, [vkAppUrl, vkAppUrl]);
  f.state.pending = true;
  assert.equal(f.navigation.handleBackPress(), true);
  now += 5000;
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.state.backwardCalls, 2);
  f.state.currentIndex = 0;
  assert.equal(f.navigation.handleBackPress(), true);
  assert.equal(f.closeCalls(), 1);
  assert.equal(f.state.backwardCalls, 2);
});

test('VK closed or detached sessions do not trigger stale history navigation', (t) => {
  const f = vkHistoryFixture(t, [vkAppUrl, vkAppUrl]);
  f.navigation.detach(f.endpoint);
  assert.equal(f.navigation.handleBackPress(), false);
  f.navigation.attach(f.endpoint);
  f.session.close();
  assert.equal(f.navigation.handleBackPress(), false);
  assert.equal(f.state.backwardCalls, 0);
});
