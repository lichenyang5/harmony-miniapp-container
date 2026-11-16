const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function fixture(isChild = false) {
  let parses = 0;
  class PlatformURL extends URL {
    constructor(address) { super(address); parses++; }
    get params() { return this.searchParams; }
  }
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineLiffSchemeHandler } = load('main/ets/vendors/line/scheme/LineLiffSchemeHandler');
  const { WebSchemeDecision } = load('main/ets/web/scheme/WebSchemeTypes');
  const states = [], windows = [];
  let closes = 0, foreground = true;
  const session = { id: 'standalone-line-handler', appId: 'target-app',
    getAdapter: () => ({ getLiffId: () => undefined }), isClosed: () => false, getDocumentId: () => 7,
    lifecycle: { isForeground: () => foreground }, requestClose: () => { closes++; } };
  const handler = new LineLiffSchemeHandler({
    session, isChild,
    establishAppState: state => states.push(state),
    openSubWindow: address => windows.push(address)
  });
  const { WebSchemeDispatcher } = load('main/ets/web/scheme/WebSchemeDispatcher');
  const dispatcher = new WebSchemeDispatcher([handler]);
  const navigate = (url, isMainFrame = true, documentId = 7) => dispatcher.dispatch({ url, isMainFrame, documentId });
  return { handler, navigate, states, windows, WebSchemeDecision, background() { foreground = false; },
    parses: () => parses, closes: () => closes };
}

test('a background document can establish its app state but cannot open or close a window', () => {
  const f = fixture(); f.background();
  assert.equal(f.navigate('liff://app/target-app?feature_token=token'), f.WebSchemeDecision.CONSUME);
  assert.equal(f.states.length, 1);
  assert.equal(f.navigate('liff://subwindow?url=https%3A%2F%2Fexample.com'), f.WebSchemeDecision.BLOCK);
  assert.equal(f.navigate('liff://close'), f.WebSchemeDecision.BLOCK);
  assert.deepEqual(f.windows, []); assert.equal(f.closes(), 0);
});

test('LINE command table parses once and passes decoded app state through narrow ports', () => {
  const f = fixture();
  assert.equal(f.navigate('LIFF://app/target%2Dapp/extra?feature_token=a%2Bb'), f.WebSchemeDecision.CONSUME);
  assert.deepEqual(f.states, [{ liffId: 'target-app', featureToken: 'a+b' }]);
  assert.equal(f.parses(), 1);
  for (const address of ['liff://APP/target-app?feature_token=t', 'liff://application/x',
    'liff://username@app/target-app?feature_token=t', 'liff://app:123/x',
    'liff://close:123', 'liff://close/extra', 'liff://unknown', 'liff:app/target-app?feature_token=t']) {
    assert.equal(f.navigate(address), f.WebSchemeDecision.PASS, address);
  }
  assert.equal(f.parses(), 1, 'unknown authority must not be normalized into a known command');
});

test('LINE invalid app requests and subframes block without invoking state or window ports', () => {
  const f = fixture();
  for (const address of ['liff://app', 'liff://app/target-app',
    'liff://app/target-app?feature_token=', 'liff://app/%ZZ?feature_token=t',
    'liff://app/different?feature_token=t']) {
    assert.equal(f.navigate(address), f.WebSchemeDecision.BLOCK, address);
  }
  for (const command of ['app/target-app?feature_token=t', 'subwindow?url=x', 'close']) {
    assert.equal(f.navigate(`liff://${command}`, false), f.WebSchemeDecision.BLOCK);
    assert.equal(f.navigate(`liff://${command}`, true, 0), f.WebSchemeDecision.BLOCK);
  }
  assert.deepEqual(f.states, []);
  assert.deepEqual(f.windows, []);
  assert.equal(f.closes(), 0);
});

test('LINE window commands delegate to existing owners and dispose blocks known commands', () => {
  const root = fixture();
  assert.equal(root.navigate('liff://close'), root.WebSchemeDecision.CONSUME);
  assert.equal(root.closes(), 1);
  assert.equal(root.navigate('liff://close/?source=test#ignored'), root.WebSchemeDecision.CONSUME);
  assert.equal(root.closes(), 2);
  const address = 'liff://subwindow?url=https%3A%2F%2Fliff.line.me%2Fchild&msit=t';
  assert.equal(root.navigate(address), root.WebSchemeDecision.CONSUME);
  assert.deepEqual(root.windows, [address]);
  assert.equal(root.parses(), 0, 'window commands leave URL parsing to their existing owner');
  const child = fixture(true);
  assert.equal(child.navigate('liff://close'), child.WebSchemeDecision.CONSUME);
  assert.equal(child.closes(), 1);
  assert.equal(child.parses(), 0, 'close does not require a URL object');
  child.handler.dispose();
  child.handler.dispose();
  assert.equal(child.navigate('liff://close'), child.WebSchemeDecision.BLOCK);
  assert.equal(child.navigate('liff://app/target-app?feature_token=t'), child.WebSchemeDecision.BLOCK);
  assert.equal(child.closes(), 1);
  assert.deepEqual(child.states, []);
});
