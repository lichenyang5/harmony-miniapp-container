const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');
class PlatformURL extends URL { get params() { return this.searchParams; } }
const loadSDK = () => createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
  { '@kit.ArkTS': { url: { URL: PlatformURL } } });

function session(load, adapter, id = 'mode') {
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  return new MiniAppSession(id, {
    info: { appId: 'app-id', vendor: 'line', url: 'https://liff.line.me/app-id',
      customUserAgent: 'Mozilla/5.0 Line/26.15.1 LIFF', extraUserAgentParams: { Line: '26.15.1' } },
    adapter, vendor: new LineVendor(), swipeBackController: { dispose() {} }
  }, {});
}

test('WEB mode excludes LINE bridge, MST, native account and LIFF navigation handling', async () => {
  const load = loadSDK();
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const adapter = new LineAdapter({ mode: 'web', account: {
    restoreSession() { assert.fail('WEB must not restore an account'); },
    addInvalidationListener() { assert.fail('WEB must not observe a native account'); }
  } });
  const s = session(load, adapter);
  const b = s.getBinding();
  assert.equal(adapter.getAccount(), undefined);
  assert.deepEqual(b.injections, []);
  assert.equal(b.scripts.length, 1);
  assert.equal(b.scripts[0].required, true);
  assert.deepEqual(b.scripts[0].scriptRules, ['*']);
  assert.equal(b.getModalSessionToken(), undefined);
  assert.equal(s.info.customUserAgent,
    'Mozilla/5.0 (Phone; OpenHarmony 5.0; Android 14) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile');
  assert.equal(s.info.extraUserAgentParams, undefined);
  const prepared = await b.prepareInitialLoad();
  assert.equal(prepared.url, s.initialUrl);
  assert.deepEqual(prepared.headers, []);
  assert.deepEqual(b.createWebSchemeHandlers().map(handler => handler.id), ['web.system']);
  const evaluated = [];
  s.attach({ evaluate(script) { evaluated.push(script); return Promise.resolve(''); } });
  s.beginDocument(s.initialUrl);
  b.onPageFinished(s.getDocumentId());
  assert.equal(evaluated.length, 1);
  assert.equal(evaluated[0], b.scripts[0].script);
  assert.equal(s.interceptWebScheme({ url: 'liff://app/app-id?feature_token=web',
    isMainFrame: true, documentId: s.getDocumentId() }), false);
  assert.equal(b.getAppState(), undefined);
  s.close();
});

test('WEB mode skips the LINE browser guide and preserves other pages', () => {
  const { createLineWebDirectLaunchScript } = loadSDK()('main/ets/vendors/line/script/LineWebDirectLaunch');
  const script = createLineWebDirectLaunchScript().script;
  let replacedUrl;
  let observed = false;
  let mutationCallback;
  const windowObject = {};
  windowObject.top = windowObject;
  const guideContext = {
    window: windowObject,
    location: {
      hostname: 'miniapp.line.me',
      href: 'https://miniapp.line.me/2012241484-PibjtMII',
      replace(url) { replacedUrl = url; }
    },
    document: {
      getElementById() { return null; },
      addEventListener() {}
    },
    MutationObserver: class {
      constructor(callback) { mutationCallback = callback; }
      observe() { observed = true; }
      disconnect() {}
    },
    console: { info() {}, warn() {} },
    URL,
    setTimeout() {}
  };
  vm.runInNewContext(script, guideContext);
  assert.equal(replacedUrl, undefined);
  assert.equal(observed, true);
  windowObject.liffInfo = {
    liffAppUrlForBrowser:
      'https://hanpeizhao.github.io/lineDemo/?liff.source=lp_link&liff.via=lp_link'
  };
  assert.equal(replacedUrl,
    'https://hanpeizhao.github.io/lineDemo/?liff.source=lp_link&liff.via=lp_link');
  assert.equal(typeof mutationCallback, 'function');

  let unrelatedRedirected = false;
  const unrelatedWindow = {};
  unrelatedWindow.top = unrelatedWindow;
  vm.runInNewContext(script, {
    window: unrelatedWindow,
    location: {
      hostname: 'hanpeizhao.github.io',
      href: 'https://hanpeizhao.github.io/lineDemo/',
      replace() { unrelatedRedirected = true; }
    },
    document: {},
    MutationObserver: class {},
    console: { info() {}, warn() {} },
    URL,
    setTimeout() {}
  });
  assert.equal(unrelatedRedirected, false);
});

test('removed CLIENT_WEB_LOGIN mode is rejected without falling back to another mode', () => {
  const { LineAdapter } = loadSDK()('main/ets/vendors/line/LineAdapter');
  assert.throws(() => new LineAdapter({ mode: 'clientWebLogin' }),
    error => error.code === 'INVALID_ARGUMENT');
});

test('invalid LINE mode fails before opening a session', () => {
  const { LineAdapter } = loadSDK()('main/ets/vendors/line/LineAdapter');
  assert.throws(() => new LineAdapter({ mode: 'typo' }), error => error.code === 'INVALID_ARGUMENT');
});

test('SDK default account is lazy and shared across native adapters while WEB ignores it', () => {
  let applicationContexts = 0;
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined, {
    '@kit.BasicServicesKit': { deviceInfo: { productModel: 'Test Model', sdkApiVersion: 22 } },
    '@kit.LocalizationKit': { i18n: { System: { getSystemLocale: () => 'en-US', getSystemRegion: () => 'US' } } }
  });
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineDefaultAccount } = load('main/ets/vendors/line/auth/LineDefaultAccount');
  const first = new LineAdapter({ mode: 'client' });
  const second = new LineAdapter({ mode: 'client' });
  assert.equal(first.getAccount(), undefined);
  const context = { getApplicationContext() { applicationContexts++; return {}; } };
  const account = LineDefaultAccount.get(context);
  assert.equal(LineDefaultAccount.get(context), account);
  assert.equal(first.getAccount(), account);
  assert.equal(second.getAccount(), account);
  assert.equal(new LineAdapter({ mode: 'web' }).getAccount(), undefined);
  assert.equal(applicationContexts, 1);
});

test('native mode restores first and discards a pending login when the owning session closes', async () => {
  const load = loadSDK();
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  let finish;
  let issuances = 0;
  const account = { getVersion: () => 1, addInvalidationListener() {}, removeInvalidationListener() {},
    restoreSession: () => new Promise(resolve => { finish = resolve; }),
    sendLiffRpc() { issuances++; assert.fail('closed container must not issue LIFF'); } };
  const s = session(load, new LineAdapter({ mode: 'client', account }));
  const pending = s.getBinding().prepareInitialLoad();
  const rejected = assert.rejects(pending, error => error.code === 'LINE_LOGIN_CANCELLED' || error.code === 'LINE_SESSION_CLOSED');
  for (let i = 0; i < 20 && !finish; i++) await new Promise(resolve => setImmediate(resolve));
  assert.equal(typeof finish, 'function');
  assert.equal(issuances, 0);
  s.close();finish(true);await rejected;
  assert.equal(issuances, 0);
});
