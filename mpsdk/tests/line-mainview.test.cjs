const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

class PlatformURL extends URL { get params() { return this.searchParams; } }
function string(value) { const b = Buffer.from(value); return [b.length, ...b]; }
function response(sequence = 1, viewType, liffId = 'app-id') {
  return Uint8Array.from([0x82, 0x41, sequence, ...string('issueLiffView'), 0x0c, 0,
    0x1c, ...(viewType === undefined ? [0x28] : [0x18, ...string(viewType), 0x18]),
    ...string('https://app.example/start'), 0,
    0x18, ...string('context'), 0x18, ...string('liff-access'),
    0x18, ...string('feature'), 0x28, ...string('client-id'),
    0x18, ...string('id-token'), 0x19, 0x18, ...string('profile'),
    0x78, ...string(liffId), 0, 0]);
}

test('a Mini App alias keeps its launch identity while issued LIFF identity drives MST, bridge and OAuth', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { WebSchemeDecision } = load('main/ets/web/scheme/WebSchemeTypes');
  const alias = 'buruburudobutsu', canonical = '2007326019-vAg8J6Bp';
  const requests = [], loads = [];
  const account = { restoreSession: async () => true, getVersion: () => 1,
    requireAccessToken: () => 'account', addInvalidationListener() {}, removeInvalidationListener() {},
    sendLiffRpc: async (method, body, liffId) => {
      requests.push({ method, body, liffId }); return response(1, undefined, canonical);
    },
    sendAccountRpc: async request => {
      requests.push(request);
      const target = 'https://app.example/oauth-callback';
      return Uint8Array.from([0x82, 0x41, 1, ...string(request.method),
        0x0c, 0, 0x18, ...string(target), 0, 0]);
    }
  };
  const session = new MiniAppSession('alias-main', {
    info: { appId: alias, vendor: 'line', url: `https://miniapp.line.me/${alias}` },
    adapter: new LineAdapter({ mode: 'client', account }), vendor: new LineVendor(), swipeBackController: { dispose() {} }
  }, {});
  session.attach({ evaluate: async () => '', load: (...args) => loads.push(args) });
  session.lifecycle.setHostForeground(true);
  const binding = session.getBinding();
  const handlers = binding.createWebSchemeHandlers();
  try {
    assert.deepEqual(binding.scripts, [], 'MST scripts must wait for the issued identity');
    const prepared = await binding.prepareInitialLoad();
    assert.equal(requests[0].liffId, alias);
    assert.equal(session.appId, alias, 'host identity must remain stable');
    assert.equal(binding.getAppState().liffId, canonical);
    assert.ok(binding.scripts.some(script => script.script.includes(`LIFF_STORE:${canonical}:mstChallenge`)));
    assert.ok(binding.scripts.every(script => !script.script.includes(`LIFF_STORE:${alias}:`)));
    session.beginDocument(prepared.url);
    const appHandler = handlers.find(handler => handler.id === 'line.liff');
    assert.equal(appHandler.handle({ url: `liff://app/${canonical}?feature_token=feature`,
      isMainFrame: true, documentId: session.getDocumentId() }, { proceed: () => WebSchemeDecision.PASS }),
      WebSchemeDecision.CONSUME);
    await binding.prepareNavigation(`https://miniapp.line.me/${alias}`);
    await binding.prepareNavigation(`https://liff.line.me/${canonical}`);
    assert.ok(requests.slice(1).every(request => request.liffId === canonical));
    await assert.rejects(binding.prepareNavigation('https://miniapp.line.me/unrelated'), { code: 'INVALID_ARGUMENT' });
    const oauth = handlers.find(handler => handler.id === 'line.webLogin');
    oauth.handle({ url: 'https://access.line.me/oauth2/v2.1/login', isMainFrame: true }, { proceed: () => 42 });
    for (let i = 0; i < 20 && loads.length === 0; i++) await new Promise(resolve => setImmediate(resolve));
    assert.equal(requests.at(-1).liffId, canonical);
    assert.equal(loads.length, 1);
    account.sendLiffRpc = async () => response(1, undefined, 'unrelated-app');
    await assert.rejects(binding.prepareNavigation(`https://miniapp.line.me/${alias}`), { code: 'LINE_MAINVIEW_INVALID' });
    assert.equal(binding.getAppState().liffId, canonical);
  } finally { handlers.forEach(handler => handler.dispose?.()); session.close(); }
});

test('main view issuance preserves view.type in the prepared result', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineMainViewService } = load('main/ets/vendors/line/liff/LineMainViewService');
  for (const viewType of [undefined, 'FULL', 'TALL', '', 'FUTURE']) {
    const service = new LineMainViewService({ sendLiffRpc: async () => response(1, viewType) });
    const result = await service.issue('app-id', 'https://liff.line.me/app-id', 'challenge');
    assert.equal(result.viewType, viewType);
    assert.equal(result.accessToken, 'liff-access');
  }
});

test('main view opens official consent, closes it before reissuing and loads app-specific credentials', async () => {
  global.DialogAlignment = { Center: 0 };
  let params; let closed = 0; let disposed = 0; let calls = 0;
  const prompt = {
    openCustomDialog: async content => { params = content.params; },
    closeCustomDialog: async () => { closed++; }
  };
  class Content {
    constructor(_context, _builder, value) { this.params = value; }
    dispose() { disposed++; }
  }
  const load = createLoader(undefined, undefined,
    { getLastWindow: async () => ({ getUIContext: () => ({ getPromptAction: () => prompt }) }) },
    undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } }, '@kit.ArkUI': { ComponentContent: Content } });
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const listeners = new Set();
  const account = { restoreSession: async () => true, getVersion: () => 1,
    addInvalidationListener: listener => listeners.add(listener),
    removeInvalidationListener: listener => listeners.delete(listener),
    getWebAuthHeaders: () => ({ 'X-Line-Access': 'native-account', 'X-Line-Application': 'native-profile' }),
    sendLiffRpc: async () => {
      if (++calls === 1) return Uint8Array.from([0x82, 0x41, 1, ...string('issueLiffView'),
        0x1c, 0x15, 6, 0x2c, 0x3c, 0x18, ...string('channel'),
        0x18, ...string('https://access.line.me/dialog/consent'), 0, 0, 0, 0]);
      assert.equal(closed, 1, 'issuance must wait for the consent dialog to close');
      return response(calls);
    }
  };
  const session = new MiniAppSession('consent-main', {
    info: { appId: 'app-id', vendor: 'line', url: 'https://liff.line.me/app-id' },
    adapter: new LineAdapter({ mode: 'client', account }), vendor: new LineVendor(), swipeBackController: { dispose() {} }
  }, {});
  const pending = session.getBinding().prepareInitialLoad();
  for (let i = 0; i < 30 && !params; i++) await new Promise(resolve => setImmediate(resolve));
  assert.ok(params);
  assert.equal(params.url, 'https://access.line.me/dialog/consent');
  assert.equal(params.headers.find(x => x.headerKey === 'X-Line-Access').headerValue, 'native-account');
  params.complete(true);
  const prepared = await pending;
  assert.equal(calls, 2);assert.equal(disposed, 1);
  assert.equal(prepared.headers[0].name, 'X-LINE-LIFF-TOKEN');
  assert.equal(prepared.headers[0].value, 'liff-access');
  assert.equal(params.headers.length, 0, 'disposed page must release its account headers');
  session.close();
  assert.equal(listeners.size, 0);
});
function v1Response() {
  return Uint8Array.from([0x82, 0x41, 1, ...string('issueLiffView'), 0x0c, 0,
    0x1c, 0x28, ...string('https://app.example/start'), 0,
    0x18, ...string('context'), 0x18, ...string('liff-access'),
    0x18, ...string('feature'), 0x59, 0x15, 2,
    0x68, ...string('app-id'), 0, 0]);
}

function directLinkResponse(endpoint, options = [2]) {
  return Uint8Array.from([0x82, 0x41, 1, ...string('issueLiffView'), 0x0c, 0,
    0x1c, 0x28, ...string(endpoint), 0,
    0x18, ...string('context'), 0x18, ...string('liff-access'),
    0x18, ...string('feature'), 0x59, (options.length << 4) | 5, ...options.map(value => value * 2),
    0x68, ...string('app-id'), 0, 0]);
}

test('V2 direct links append state path, append query values and replace fragment before credentials', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineMainViewService } = load('main/ets/vendors/line/liff/LineMainViewService');
  const service = new LineMainViewService({ sendLiffRpc: async () =>
    directLinkResponse('https://app.example/base/?tag=base#old', [1, 2]) });
  const state = '/detail%20page?tag=one&tag=two&liff.preferCachedInstance=true#section';
  const result = await service.issue('app-id',
    'https://liff.line.me/app-id?outer=kept&liff.domain=ignored&liff.referrer=ignored&liff.state=' +
      encodeURIComponent(state), 'challenge');
  const parsed = new URL(result.url);
  assert.equal(parsed.origin, 'https://app.example');
  assert.equal(parsed.pathname, '/base/detail%20page');
  assert.deepEqual(parsed.searchParams.getAll('tag'), ['base', 'one', 'two']);
  assert.equal(parsed.searchParams.get('outer'), 'kept');
  for (const key of ['liff.state', 'liff.preferCachedInstance', 'liff.domain', 'liff.referrer']) {
    assert.equal(parsed.searchParams.has(key), false);
  }
  assert.equal(parsed.hash, '#section&context_token=context&access_token=liff-access&feature_token=feature' +
    '&id_token=&client_id=&mst_challenge=challenge');
});

test('V2 query-only, empty and relative states preserve endpoint origin and path boundaries', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineMainViewService } = load('main/ets/vendors/line/liff/LineMainViewService');
  for (const [state, pathname, value, fragment] of [
    ['?liff.preferCachedInstance=true&id=7', '/base', '7', 'context_token='],
    ['detail?id=8#next', '/base/detail', '8', 'next&context_token='],
    ['//other.example/path?id=9', '/base//other.example/path', '9', 'context_token='],
    ['?liff.preferCachedInstance=true', '/base', null, 'old&context_token='],
    ['', '/base', null, 'old&context_token='],
    ['/', '/base', null, 'old&context_token=']
  ]) {
    const service = new LineMainViewService({ sendLiffRpc: async () =>
      directLinkResponse('https://app.example/base#old') });
    const result = await service.issue('app-id',
      'https://liff.line.me/app-id?liff.state=' + encodeURIComponent(state), 'challenge');
    const parsed = new URL(result.url);
    assert.equal(parsed.origin, 'https://app.example', state);
    assert.equal(parsed.pathname, pathname, state);
    assert.equal(parsed.searchParams.get('id'), value, state);
    assert.equal(parsed.searchParams.has('liff.state'), false, state);
    assert.equal(parsed.searchParams.has('liff.preferCachedInstance'), false, state);
    assert.ok(parsed.hash.startsWith('#' + fragment), state);
  }
});

test('ordinary launch keeps liff.state for the web SDK and preserves endpoint fragment', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineMainViewService } = load('main/ets/vendors/line/liff/LineMainViewService');
  const service = new LineMainViewService({ sendLiffRpc: async () =>
    directLinkResponse('https://app.example/base#old', []) });
  const state = '/detail?id=7#section';
  const result = await service.issue('app-id',
    'https://liff.line.me/app-id?liff.state=' + encodeURIComponent(state), 'challenge');
  const parsed = new URL(result.url);
  assert.equal(parsed.pathname, '/base');
  assert.equal(parsed.searchParams.get('liff.state'), state);
  assert.ok(parsed.hash.startsWith('#old&context_token='));
});

test('issueLiffView uses the shared request struct without child msit', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  const bytes = LineSubViewCodec.encodeMain('app-id', 'https://liff.line.me/app-id', 'liff.line.me', 1);
  assert.deepEqual(Array.from(bytes), [0x82, 0x21, 1, ...string('issueLiffView'),
    0x1c, 0x18, ...string('app-id'), 0x1c, 0x1c, 0, 0,
    0x42, 0x18, ...string('liff.line.me'), 0x28,
    ...string('https://liff.line.me/app-id'), 0, 0]);
  assert.equal(LineSubViewCodec.decode(response(), 1, 'issueLiffView').accessToken, 'liff-access');
});

test('V1 direct link response is reported explicitly before loading the wrong fragment', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineMainViewService } = load('main/ets/vendors/line/liff/LineMainViewService');
  const service = new LineMainViewService({ sendLiffRpc: async () => v1Response() });
  await assert.rejects(service.issue('app-id', 'https://liff.line.me/app-id', 'challenge'),
    error => error.code === 'LINE_MAINVIEW_DIRECT_LINK_V1_UNSUPPORTED');
});

test('LINE binding issues the main view before loading and retains account-scoped view credentials', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const calls = [];
  const adapter = new LineAdapter({ mode: 'client', account: { restoreSession: async () => true, getVersion: () => 1,
    addInvalidationListener() {}, removeInvalidationListener() {},
    sendLiffRpc: async (method, body, liffId) => {
    calls.push({ method, body, liffId });
    return response();
  } } });
  const session = new MiniAppSession('main', {
    info: { appId: 'app-id', vendor: 'line', url: 'https://liff.line.me/app-id?foo=bar' },
    adapter, vendor: new LineVendor(), swipeBackController: { dispose() {} }
  }, {});
  const binding = session.getBinding();
  const prepared = await binding.prepareInitialLoad();
  assert.equal(calls[0].method, 'issueLiffView');
  assert.equal(calls[0].liffId, 'app-id');
  assert.equal(new URL(prepared.url).searchParams.get('foo'), 'bar');
  assert.match(prepared.url, /#context_token=context&access_token=liff-access&feature_token=feature/);
  assert.match(prepared.url, /&mst_challenge=/);
  assert.equal(prepared.headers[0].name, 'X-LINE-LIFF-TOKEN');
  assert.equal(prepared.headers[0].value, 'liff-access');
  assert.equal(binding.getAppState().featureToken, 'feature');
  const challenge = binding.getModalSessionToken();
  session.beginDocument('');
  const target = 'https://liff.line.me/app-id?liff.state=%2Fnext%3Fx%3D1';
  const navigationRequest = await binding.prepareNavigation(target);
  assert.equal(calls.length, 2);
  assert.equal(calls[1].method, 'issueLiffView');
  assert.equal(new URL(navigationRequest.url).searchParams.get('liff.state'), '/next?x=1');
  assert.equal(new URL(navigationRequest.url).searchParams.has('foo'), false);
  assert.deepEqual(binding.getModalSessionToken(), challenge);
  assert.equal(navigationRequest.headers[0].value, 'liff-access');
  session.close();
});

test('main view authorization is discarded when the account changes before delivery', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  let finish;
  let version = 1;
  const adapter = new LineAdapter({ mode: 'client', account: { restoreSession: async () => true, getVersion: () => version,
    addInvalidationListener() {}, removeInvalidationListener() {},
    sendLiffRpc: async () => new Promise(resolve => { finish = resolve; }) } });
  const session = new MiniAppSession('main', {
    info: { appId: 'app-id', vendor: 'line', url: 'https://liff.line.me/app-id' },
    adapter, vendor: new LineVendor(), swipeBackController: { dispose() {} }
  }, {});
  const binding = session.getBinding();
  const pending = binding.prepareInitialLoad();
  while (!finish) await new Promise(resolve => setImmediate(resolve));
  version++;
  finish(response());
  await assert.rejects(pending, error => error.code === 'LINE_LOGIN_CANCELLED');
  assert.equal(binding.getAppState(), undefined);
  session.close();
});

test('logout closes an attached LINE session and removes its account listener', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineAccountManager } = load('main/ets/vendors/line/auth/LineAccountManager');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const manager = new LineAccountManager({ cancel() {}, login: async () => ({
    mid: 'mid', accessToken: 'access', refreshToken: 'refresh', certificate: 'cert',
    loginSessionId: 'session', durationUntilRefreshInSec: 300, metaData: new Map()
  }) }, 'device', 'model');
  await manager.startQrLogin(() => {});
  let closeNotifications = 0;
  const session = new MiniAppSession('main', {
    info: { appId: 'app-id', vendor: 'line', url: 'https://liff.line.me/app-id' },
    adapter: new LineAdapter({ mode: 'client', account: manager }), vendor: new LineVendor(),
    swipeBackController: { dispose() {} }, onClose: () => { closeNotifications++; }
  }, {});
  manager.logout();
  assert.equal(closeNotifications, 1);
  assert.throws(() => session.getBinding(), error => error.code === 'SESSION_CLOSED');
  manager.logout();
});

test('failed navigation retains account invalidation ownership and never restarts login', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const listeners = new Set(); let issueCount = 0; let loginCount = 0;
  const account = { restoreSession: async () => { loginCount++; return true; }, getVersion: () => 1,
    addInvalidationListener(listener) { listeners.add(listener); },
    removeInvalidationListener(listener) { listeners.delete(listener); },
    async sendLiffRpc() { if (++issueCount > 1) throw Error('issue failed'); return response(); }
  };
  const session = new MiniAppSession('navigation-account', {
    info: { appId: 'app-id', vendor: 'line', url: 'https://liff.line.me/app-id' },
    adapter: new LineAdapter({ mode: 'client', account }), vendor: new LineVendor(), swipeBackController: { dispose() {} }
  }, {});
  const binding = session.getBinding(); await binding.prepareInitialLoad();
  const initialLoginCount = loginCount; session.beginDocument('');
  await assert.rejects(binding.prepareNavigation('https://liff.line.me/app-id?liff.state=next'));
  assert.equal(loginCount, initialLoginCount);
  assert.equal(listeners.size, 1);
  for (const listener of [...listeners]) listener();
  assert.throws(() => session.getBinding(), error => error.code === 'SESSION_CLOSED');
  assert.equal(listeners.size, 0);
});


test('LINE navigation only accepts the current app on fixed HTTPS entry origins before preparing credentials', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineMode } = load('main/ets/vendors/line/LineMode');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const session = new MiniAppSession('navigation-url', {
    info: { appId: 'app-id', vendor: 'line', url: 'https://liff.line.me/app-id' },
    adapter: new LineAdapter({ mode: LineMode.WEB }), vendor: new LineVendor(),
    swipeBackController: { dispose() {} }
  }, {});
  const binding = session.getBinding();
  const calls = [];
  binding.prepareLoad = async address => { calls.push(address); return { url: address }; };
  for (const address of [
    'https://liff.line.me/app-id?liff.state=%2Fnext&x=1&x=2#target',
    'https://miniapp.line.me/app-id?liff.source=lp_link',
    'https://LIFF.LINE.ME/%61pp-id'
  ]) {
    assert.equal((await binding.prepareNavigation(address)).url, address);
  }
  const accepted = calls.length;
  for (const address of [
    'https://liff.line.me/other', 'https://miniapp.line.me/app-id-other',
    'https://liff.line.me/app-id/extra', 'https://liff.line.me/app-id/',
    'https://liff.line.me/other/../app-id', 'https://liff.line.me//app-id',
    'https://liff.line.me/app-id%2Fextra', 'https://liff.line.me/%invalid',
    'http://liff.line.me/app-id', 'https://liff.line.me.evil.example/app-id',
    'https://user@liff.line.me/app-id', 'https://liff.line.me:444/app-id',
    'https://example.com/app-id', 'https://liff.line.me/app-id\\extra'
  ]) {
    await assert.rejects(binding.prepareNavigation(address), error => error.code === 'INVALID_ARGUMENT', address);
  }
  assert.equal(calls.length, accepted, 'invalid targets must not issue credentials');
  session.close();
});


test('intercepted encoded LIFF state follows APK wrapping before V2 and ordinary issuance', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineLiffLinkSchemeHandler } = load('main/ets/vendors/line/scheme/LineLiffLinkSchemeHandler');
  const { WebSchemeDispatcher } = load('main/ets/web/scheme/WebSchemeDispatcher');
  const { WebSchemeDecision: D } = load('main/ets/web/scheme/WebSchemeTypes');
  const { LineMainViewService } = load('main/ets/vendors/line/liff/LineMainViewService');
  const state = '/detail%20page?tag=one&tag=two#section';
  for (const [scheme, host, path, key] of [
    ['https', 'liff.line.me', '/app-id', 'liff.state'],
    ['https', 'miniapp.line.me', '/app-id/', 'liff.state'],
    ['http', 'liff.line.me', '//app-id', 'liff%2Estate']
  ]) {
    for (const v2 of [true, false]) {
      let target;
      const originalQuery = '?outer=kept&' + key + '=' + encodeURIComponent(state);
      const dispatcher = new WebSchemeDispatcher([new LineLiffLinkSchemeHandler({
        session: { id: 'encoded-state', appId: 'source', isClosed: () => false, getDocumentId: () => 1,
          getAdapter: () => ({ getLiffId: () => undefined }), lifecycle: { isForeground: () => true },
          isDocumentFinished: () => true, requestOpenMiniApp: async app => { target = app; } },
        canTransition: () => true
      })]);
      try {
        assert.equal(dispatcher.dispatch({ url: scheme + '://' + host + path + originalQuery,
          isMainFrame: true, documentId: 1 }), D.CONSUME);
        assert.equal(target.appId, 'app-id');
        assert.equal(target.url, 'https://' + host + '/app-id?liff.state=' + encodeURIComponent(originalQuery));
        const service = new LineMainViewService({ sendLiffRpc: async () =>
          directLinkResponse('https://app.example/base/', v2 ? [2] : []) });
        const issued = new URL((await service.issue(target.appId, target.url, 'challenge')).url);
        assert.equal(issued.pathname, '/base/');
        if (v2) {
          assert.equal(issued.searchParams.get('outer'), 'kept');
          assert.equal(issued.searchParams.get('liff.state'), state);
        } else {
          assert.equal(issued.searchParams.get('outer'), null);
          assert.equal(issued.searchParams.get('liff.state'), originalQuery);
        }
      } finally { dispatcher.dispose(); }
    }
  }
});
