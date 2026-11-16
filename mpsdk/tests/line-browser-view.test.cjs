const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const { createLoader } = require('./sdk-loader.cjs');

// Execute real component methods; declarative build/rendering remains a device concern.
function viewFixture(nativeAuth, isAvailable = () => true) {
  const source = fs.readFileSync(path.join(__dirname,
    '../src/main/ets/vendors/line/browser/LineBrowserView.ets'), 'utf8');
  const parsed = ts.createSourceFile('LineBrowserView.ts', source.replace('struct LineBrowserView', 'class LineBrowserView'),
    ts.ScriptTarget.ES2021, true);
  const declaration = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'LineBrowserView');
  assert.ok(declaration);
  const members = declaration.members.filter(node => ts.isPropertyDeclaration(node) ||
    (ts.isMethodDeclaration(node) && node.name.getText(parsed) !== 'build' &&
      !ts.getDecorators(node)?.some(decorator => decorator.expression.getText(parsed) === 'Builder'))).map(node =>
    ts.isPropertyDeclaration(node) ? ts.factory.updatePropertyDeclaration(node,
      node.modifiers?.filter(modifier => !ts.isDecorator(modifier)), node.name, node.questionToken, node.type, node.initializer) : node);
  const printed = ts.createPrinter().printNode(ts.EmitHint.Unspecified,
    ts.factory.createClassDeclaration(undefined, 'LineBrowserView', undefined, undefined, members), parsed);
  const javascript = ts.transpileModule(printed, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
  const operations = [], toasts = [];
  class Controller {
    getUrl() { return 'https://example.test'; }
    accessBackward() { return true; }
    backward() { operations.push('back'); }
    stop() { operations.push('stop'); }
    refresh() { operations.push('refresh'); }
    loadUrl(address) { operations.push(address); }
  }
  class Response {
    setResponseCode(code) { this.code = code; }
    setResponseData(data) { this.data = data; }
    setResponseEncoding(value) { this.encoding = value; }
    setResponseMimeType(value) { this.mime = value; }
    setReasonMessage(value) { this.reason = value; }
    setResponseIsReady(value) { this.ready = value; }
  }
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } } });
  const { validateLineBrowserUrl } = load('main/ets/vendors/line/browser/LineBrowserUrl');
  const { WebSchemeDispatcher } = load('main/ets/web/scheme/WebSchemeDispatcher');
  const { WebSchemeDecision } = load('main/ets/web/scheme/WebSchemeTypes');
  const { WebSystemSchemeHandler } = load('main/ets/web/scheme/WebSystemSchemeHandler');
  const { LineBrowserAppSchemeHandler } = load('main/ets/vendors/line/scheme/LineBrowserAppSchemeHandler');
  const { LineWebLoginSchemeHandler } = load('main/ets/vendors/line/scheme/LineWebLoginSchemeHandler');
  const { validateLineWebLoginReturn } = load('main/ets/vendors/line/weblogin/LineWebLoginUrl');
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  const { SdkLogger } = load('main/ets/logging/SdkLogger');
  const View = new Function('webview', 'validateLineBrowserUrl', 'readLineDialogInsets', 'WebResourceResponse',
    'WebSchemeDispatcher', 'LineBrowserAppSchemeHandler', 'LineWebLoginSchemeHandler', 'WebSystemSchemeHandler',
    'validateLineWebLoginReturn', 'MiniAppError', 'DOCUMENT_CHANGED', 'SdkLogger', '$r', 'WebSchemeDecision', 'LINE_WEB_USER_AGENT',
    `${javascript}; return LineBrowserView;`)({ WebviewController: Controller }, validateLineBrowserUrl,
    () => ({ top: 12, right: 0, bottom: 20, left: 0 }), Response, WebSchemeDispatcher, LineBrowserAppSchemeHandler,
    LineWebLoginSchemeHandler, WebSystemSchemeHandler, validateLineWebLoginReturn, MiniAppError, 'DOCUMENT_CHANGED', SdkLogger, name => name,
    WebSchemeDecision, 'test-UA');
  const view = new View();
  let backCallback, removed = 0, closed = 0;
  const openedApps = [];
  view.params = { url: 'https://example.test', nativeAuth, isAvailable, close() { closed++; },
    async openMiniApp(app) { openedApps.push(app); },
    hostWindow: { on(_event, callback) { backCallback = callback; }, off() { removed++; } } };
  view.getUIContext = () => ({ getHostContext: () => ({}), px2vp: value => value,
    getPromptAction: () => ({ showToast: value => toasts.push(value) }) });
  return { view, operations, openedApps, toasts, get removed() { return removed; }, get closed() { return closed; },
    changeInsets: () => backCallback({}) };
}

test('native popup keeps its bound controller, accepts blank startup and leaves HTTP navigation in that window', () => {
  const { view, openedApps } = viewFixture();
  const operations = [];
  const controller = { setCustomUserAgent: ua => operations.push(ua), loadUrl: () => assert.fail('must not replace native navigation') };
  view.params.popupController = controller; view.params.url = '';
  view.aboutToAppear(); view.attachController();
  assert.equal(view.controller, controller);
  assert.equal(view.failed, false); assert.deepEqual(operations, ['test-UA']);
  for (const url of ['', 'about:blank', 'https://liff.line.me/123-App', 'https://example.test/picker']) {
    assert.equal(view.interceptNavigation({ url, isMainFrame: true }), false);
  }
  for (const url of ['file:///a', 'javascript:alert(1)', 'https://u:p@example.test']) {
    assert.equal(view.interceptNavigation({ url, isMainFrame: true }), true);
  }
  assert.deepEqual(openedApps, []);
});

test('browser blocks local subresources while preserving normal network responses', () => {
  const { view } = viewFixture(); view.aboutToAppear();
  for (const address of ['file:///data/a', 'FILE:///data/a', 'content://media/a', 'resource://rawfile/a']) {
    const response = view.interceptResource(address);
    assert.equal(response.code, 403); assert.equal(response.data, ''); assert.equal(response.ready, true);
  }
  for (const address of ['https://example.test/a.js', 'http://example.test/image.png', 'data:image/png,abc', 'blob:https://example.test/a']) {
    assert.equal(view.interceptResource(address), null);
  }
});

function nativeFixture(send) {
  const listeners = new Set();
  const account = { getVersion: () => 1, requireAccessToken: () => 'native-token',
    addInvalidationListener: fn => listeners.add(fn), removeInvalidationListener: fn => listeners.delete(fn),
    sendAccountRpc: send };
  const { LineAdapter } = createLoader()('main/ets/vendors/line/LineAdapter');
  return { adapter: new LineAdapter({ mode: 'client', account }), lifecycle: { isForeground: () => true },
    consent: { request() { assert.fail('Unexpected consent'); } }, listeners };
}

test('browser OAuth is entry-local and loads its own WebView without native headers', async () => {
  const { reply } = require('./fixtures/line-web-login-rpc.cjs');
  const calls = [];
  const native = nativeFixture(async request => { calls.push(request); return reply('browser', request.method, 1,
    { returnUrl: 'https://shop.example/callback?state=a%2Bb' }); });
  const first = viewFixture(native), second = viewFixture(native);
  first.view.aboutToAppear(); second.view.aboutToAppear();
  first.view.attached = true; second.view.attached = true;
  first.view.schemeDispatcher.dispatch({ url: 'https://access.line.me/oauth2/v2.1/login?state=original', isMainFrame: true });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls.length, 1); assert.equal(calls[0].path, '/CH4');
  assert.deepEqual(first.operations, ['https://shop.example/callback?state=a%2Bb']); assert.deepEqual(second.operations, []);
  assert.equal(native.listeners.size, 0);
  first.view.aboutToDisappear(); second.view.aboutToDisappear();
});

test('browser document changes and entry release suppress late OAuth loads', async () => {
  const { reply } = require('./fixtures/line-web-login-rpc.cjs');
  for (const action of ['navigate', 'release', 'background']) {
    let resolve, available = true;
    const native = nativeFixture(request => new Promise(yes => { resolve = () => yes(reply('browser', request.method, 1,
      { returnUrl: 'https://shop.example/callback' })); }));
    const f = viewFixture(native, () => available); f.view.aboutToAppear(); f.view.attached = true;
    f.view.schemeDispatcher.dispatch({ url: 'https://access.line.me/oauth2/v2.1/login', isMainFrame: true });
    if (action === 'navigate') f.view.beginDocument();
    else if (action === 'release') available = false;
    else native.lifecycle.isForeground = () => false;
    resolve(); await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(f.operations, []); assert.equal(f.toasts.length, 0); assert.equal(native.listeners.size, 0);
    f.view.aboutToDisappear();
  }
});

test('OAuth failure preserves browser document and shows localized message', async () => {
  const native = nativeFixture(async () => { throw Error('network'); });
  const f = viewFixture(native); f.view.aboutToAppear(); f.view.attached = true;
  f.view.schemeDispatcher.dispatch({ url: 'https://access.line.me/oauth2/v2.1/login', isMainFrame: true });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.view.failed, false); assert.equal(f.toasts.length, 1); assert.deepEqual(f.operations, []);
  f.view.aboutToDisappear();
});

test('browser view returns through web history and removes callbacks on destruction', () => {
  const f = viewFixture(); f.view.aboutToAppear(); f.view.attached = true;
  assert.equal(f.view.params.back(), true); assert.deepEqual(f.operations, ['back']);
  f.view.reload(); assert.deepEqual(f.operations, ['back', 'refresh']);
  f.changeInsets(); assert.equal(f.view.insets.top, 12);
  f.view.aboutToDisappear(); assert.equal(f.view.params.back, undefined);
  assert.equal(f.removed, 1); assert.equal(f.operations.at(-1), 'stop');
  assert.equal(f.view.goBack(), false); f.view.fail(); assert.equal(f.view.failed, false);
});

test('retry before a valid document exists loads the original address', () => {
  const f = viewFixture(); f.view.aboutToAppear(); f.view.attached = true;
  f.view.controller.getUrl = () => 'about:blank';
  f.view.reload();
  assert.deepEqual(f.operations, ['https://example.test']);
});

test('real browser view routes a LINE deep link through its params and stops after removal', async () => {
  const f = viewFixture(); f.view.aboutToAppear();
  const request = { url: 'line://app/2006593963-DPoAqdzG?liff.source=lp_link&liff.via=lp_link', isMainFrame: true };
  const { WebSchemeDecision: D } = createLoader()('main/ets/web/scheme/WebSchemeTypes');
  for (const url of ['https://line.me/R/nv/QRCodeReader', 'line://nv/QRCodeReader']) {
    assert.equal(f.view.schemeDispatcher.dispatch({ url, isMainFrame: true }), D.PASS,
      'the ordinary browser must not consume a scanner entry');
  }
  assert.equal(f.view.schemeDispatcher.dispatch(request), D.CONSUME);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(f.openedApps, [{ appId: '2006593963-DPoAqdzG', vendor: 'line',
    url: 'https://liff.line.me/2006593963-DPoAqdzG?liff.source=lp_link&liff.via=lp_link' }]);
  f.view.aboutToDisappear();
  assert.equal(f.view.schemeDispatcher.dispatch(request), D.BLOCK);
  assert.equal(f.openedApps.length, 1);
});

test('explicit OAuth window binds component methods and checks the prepared load again', async () => {
  const native = nativeFixture(async () => { throw Error('No RPC expected'); });
  let available = true;
  const f = viewFixture(native, () => available); f.view.aboutToAppear(); f.view.attached = true;
  const handlers = f.view.createSchemeHandlers();
  const login = handlers.find(handler => handler.id === 'line.webLogin');
  const window = login.options.window;
  assert.notEqual(window, f.view);
  assert.equal(window.getDocumentId(), 0); assert.equal(window.isCurrent(0), true);
  const prepared = window.prepare('https://shop.example/callback?state=a%2Bb#done', true, 0);
  assert.equal(prepared.url, 'https://shop.example/callback?state=a%2Bb#done');
  assert.deepEqual(f.operations, []);
  available = false;
  assert.equal(window.isCurrent(0), false);
  await assert.rejects(prepared.load(), { code: 'DOCUMENT_CHANGED' });
  assert.deepEqual(f.operations, []);
  handlers.forEach(handler => handler.dispose?.()); f.view.aboutToDisappear();
});

test('ordinary browser registers system schemes without native OAuth and blocks subframe launches', () => {
  const f = viewFixture(); f.view.aboutToAppear(); f.view.attached = true;
  const handlers = f.view.createSchemeHandlers();
  assert.deepEqual(handlers.map(handler => handler.id), ['line.browser.app', 'web.system']);
  const system = handlers.find(handler => handler.id === 'web.system');
  const { WebSchemeDecision: D } = createLoader()('main/ets/web/scheme/WebSchemeTypes');
  assert.equal(system.supports({ url: 'mailto:a@b' }), true);
  assert.equal(system.handle({ url: 'tel:123', isMainFrame: false }), D.BLOCK);
  handlers.forEach(handler => handler.dispose?.()); f.view.aboutToDisappear();
});

test('bound browser window cannot deliver late errors after component destruction', async () => {
  let fail;
  const native = nativeFixture(() => new Promise((_resolve, reject) => { fail = reject; }));
  const f = viewFixture(native); f.view.aboutToAppear(); f.view.attached = true;
  f.view.schemeDispatcher.dispatch({ url: 'https://access.line.me/oauth2/v2.1/login', isMainFrame: true });
  f.view.aboutToDisappear(); fail(Error('late network error'));
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(f.operations, ['stop']); assert.deepEqual(f.toasts, []); assert.equal(native.listeners.size, 0);
});
