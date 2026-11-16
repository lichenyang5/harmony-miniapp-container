const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const { createLoader } = require('./sdk-loader.cjs');

const trusted = 'https://access.line.me/dialog/consent';

function fixture(onComplete = () => {}) {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } } });
  const { LineConsentSchemeHandler } = load('main/ets/vendors/line/scheme/LineConsentSchemeHandler');
  const { WebSchemeDispatcher } = load('main/ets/web/scheme/WebSchemeDispatcher');
  const { WebSchemeDecision } = load('main/ets/web/scheme/WebSchemeTypes');
  const { LineConsentProtocol } = load('main/ets/vendors/line/consent/LineConsentProtocol');
  let currentUrl = trusted;
  const completed = [];
  const handler = new LineConsentSchemeHandler(() => currentUrl, allowed => {
    completed.push(allowed);
    onComplete(allowed);
  });
  const dispatcher = new WebSchemeDispatcher([handler]);
  const dispatch = (url, isMainFrame = true) => dispatcher.dispatch({ url, isMainFrame });
  return { load, handler, dispatcher, dispatch, completed, WebSchemeDecision, LineConsentProtocol,
    setCurrentUrl: value => { currentUrl = value; } };
}

test('consent scheme accepts official callbacks once and leaves unrelated schemes to the owner', () => {
  for (const [command, allowed] of [['allow', true], ['retry', true], ['disallow', false]]) {
    const f = fixture();
    assert.equal(f.dispatch(trusted), f.WebSchemeDecision.PASS);
    assert.equal(f.dispatch('other://allow'), f.WebSchemeDecision.PASS);
    assert.equal(f.dispatch(`LINECONNECT://${command}`), f.WebSchemeDecision.CONSUME);
    assert.deepEqual(f.completed, [allowed]);
    assert.equal(f.dispatch('lineconnect://allow'), f.WebSchemeDecision.BLOCK);
    assert.deepEqual(f.completed, [allowed]);
  }
});

test('consent scheme blocks illegal commands, subframes, untrusted sources and disposed handlers', () => {
  const f = fixture();
  for (const address of ['lineconnect://unknown', 'lineconnect://user@allow',
    'lineconnect://allow:123', 'lineconnect://allow.evil']) {
    assert.equal(f.dispatch(address), f.WebSchemeDecision.BLOCK);
  }
  assert.equal(f.dispatch('lineconnect://allow', false), f.WebSchemeDecision.BLOCK);
  f.setCurrentUrl('https://example.com/');
  assert.equal(f.dispatch('lineconnect://allow'), f.WebSchemeDecision.BLOCK);
  f.setCurrentUrl(trusted);
  f.dispatcher.dispose();
  assert.equal(f.dispatch('lineconnect://allow'), f.WebSchemeDecision.BLOCK);
  assert.deepEqual(f.completed, []);
});

// Execute the real interception method without pretending to render an ArkUI WebView in Node.
function consentView(f) {
  const source = fs.readFileSync(path.join(__dirname,
    '../src/main/ets/vendors/line/consent/ui/LineConsentView.ets'), 'utf8');
  const parsed = ts.createSourceFile('LineConsentView.ts',
    source.replace('struct LineConsentView', 'class LineConsentView'), ts.ScriptTarget.ES2020, true);
  const declaration = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'LineConsentView');
  assert.ok(declaration, 'the actual consent view class must be present');
  const names = new Set(['aboutToDisappear', 'complete', 'fail', 'stopCallbacks', 'interceptWebScheme']);
  const methods = declaration.members.filter(node => ts.isMethodDeclaration(node) &&
    ts.isIdentifier(node.name) && names.has(node.name.text));
  assert.equal(methods.length, names.size, 'extract actual methods regardless of IDE formatting or member order');
  const js = ts.transpileModule(`class ConsentView { ${methods.map(node => node.getText(parsed)).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const { SdkLogger } = f.load('main/ets/logging/SdkLogger');
  const { MiniAppError } = f.load('main/ets/core/MiniAppError');
  const { LineErrorCode } = f.load('main/ets/vendors/line/LineErrorCode');
  const View = new Function('WebSchemeDecision', 'LineConsentProtocol', 'SdkLogger', 'MiniAppError', 'LineErrorCode',
    `${js}; return ConsentView;`)(f.WebSchemeDecision, f.LineConsentProtocol, SdkLogger, MiniAppError, LineErrorCode);
  const view = new View();
  view.active = true;
  view.finishing = false;
  view.schemeDispatcher = f.dispatcher;
  view.listening = false;
  view.proxyRegistered = false;
  view.notifications = [];
  view.browserRequests = [];
  view.logs = [];
  SdkLogger.install({ write(_level, event, details) { view.logs.push({ event, ...JSON.parse(details) }); } });
  view.params = { complete: allowed => view.notifications.push(allowed), fail: () => view.notifications.push('failed'),
    openBrowser: async address => { view.browserRequests.push(address); } };
  const { LineConsentBridge } = f.load('main/ets/vendors/line/consent/LineConsentBridge');
  view.bridge = new LineConsentBridge(() => trusted, () => view.complete(true));
  return view;
}

test('consent keeps external loads out of the credential-bearing WebView and ignores late requests', () => {
  const f = fixture();
  const view = consentView(f);
  const intercept = (url, isMainFrame = true) => view.interceptWebScheme({ url, isMainFrame });
  assert.equal(intercept(trusted), false);
  assert.equal(intercept(trusted, false), false);
  for (const address of ['https://example.com/', 'https://access.line.me.evil.test/',
    'http://access.line.me/', 'https://user@access.line.me/', 'https://access.line.me:444/',
    'other://allow', 'javascript:alert(1)', 'liff://close', 'invalid']) {
    assert.equal(intercept(address), true, address);
  }
  view.finishing = true;
  assert.equal(intercept('lineconnect://allow'), true);
  assert.equal(intercept(trusted), true);
  view.finishing = false;
  view.active = false;
  assert.equal(intercept('lineconnect://allow'), true);
  assert.deepEqual(f.completed, []);
});

test('consent forwards a top-level help link to a browser and logs the navigation without completing authorization', async () => {
  const f = fixture(); const view = consentView(f);
  const address = 'https://help.line.me/line/?contentId=200000394&utm_source=line';
  assert.equal(view.interceptWebScheme({ url: address, isMainFrame: true }), true);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(view.browserRequests, [address]);
  assert.deepEqual(view.notifications, []);
  assert.ok(view.logs.some(log => log.event === 'LineConsent.navigationReceived'));
  view.interceptWebScheme({ url: address, isMainFrame: false });
  assert.equal(view.browserRequests.length, 1);
  view.complete(false);
  view.interceptWebScheme({ url: address, isMainFrame: true });
  assert.equal(view.browserRequests.length, 1);
});

test('browser presentation failure leaves consent in place and produces a diagnostic log', async () => {
  const view = consentView(fixture());
  view.params.openBrowser = async () => { throw Error('presentation failed'); };
  assert.equal(view.interceptWebScheme({ url: 'https://help.line.me/', isMainFrame: true }), true);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(view.notifications, []);
  assert.ok(view.logs.some(log => log.event === 'LineConsent.browserOpenFailed'));
});

test('consent scheme and JS bridge share actual owner completion and cleanup gates', () => {
  for (const finish of ['scheme', 'bridge', 'deny', 'failure', 'disappear']) {
    let view;
    const f = fixture(allowed => view.complete(allowed));
    view = consentView(f);
    const request = { url: 'lineconnect://allow', isMainFrame: true };
    if (finish === 'scheme') view.interceptWebScheme(request);
    else if (finish === 'bridge') view.bridge.onUserAllowed();
    else if (finish === 'deny') view.complete(false);
    else if (finish === 'failure') view.fail();
    else view.aboutToDisappear();
    const expected = finish === 'deny' ? [false] : finish === 'failure' ? ['failed'] :
      finish === 'disappear' ? [] : [true];
    assert.deepEqual(view.notifications, expected, finish);
    assert.equal(f.dispatch(trusted), f.WebSchemeDecision.BLOCK, 'the dispatcher must be released');
    assert.equal(view.interceptWebScheme(request), true);
    view.bridge.onUserAllowed();
    view.complete(true);
    view.fail();
    view.aboutToDisappear();
    assert.deepEqual(view.notifications, expected, 'late or duplicate completion must not notify');
  }
});
