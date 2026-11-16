const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const tick = () => new Promise(resolve => setImmediate(resolve));
global.DialogAlignment = { Center: 0 };

function fixture({ pendingWindow = false, pendingOpen = false } = {}) {
  let resolveWindow; let resolveOpen;
  let content; let options; let closed = 0; let disposed = 0;
  const contents = [];
  class Content {
    constructor(_context, _builder, params) { this.params = params; content = this; contents.push(this); }
    dispose() { disposed++; }
  }
  const prompt = {
    openCustomDialog: async (_content, value) => {
      options = value;
      if (pendingOpen) await new Promise(resolve => { resolveOpen = resolve; });
    },
    closeCustomDialog: async () => { closed++; }
  };
  const hostWindow = { getUIContext: () => ({ getPromptAction: () => prompt }) };
  const load = createLoader(undefined, undefined,
    { getLastWindow: () => pendingWindow ? new Promise(resolve => { resolveWindow = resolve; }) : Promise.resolve(hostWindow) },
    undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } }, '@kit.ArkUI': { ComponentContent: Content } });
  const { LineConsentDialogHost } = load('main/ets/vendors/line/consent/ui/LineConsentDialogHost');
  const { LineConsentRequiredError } = load('main/ets/vendors/line/liff/LineConsentRequiredError');
  const host = new LineConsentDialogHost({});
  const request = () => host.request({ url: 'https://access.line.me/dialog/consent',
    headers: { 'X-Line-Access': 'private-token', 'X-Line-Application': 'native-profile' } });
  return { request, contents, finishWindow: () => resolveWindow(hostWindow), finishOpen: () => resolveOpen(),
    get content() { return content; }, get options() { return options; },
    get closed() { return closed; }, get disposed() { return disposed; } };
}

test('cancelling before the host window arrives cannot mount a late authorization dialog', async () => {
  const f = fixture({ pendingWindow: true });
  const request = f.request();
  const rejected = assert.rejects(request.result, error => error.code === 'LINE_CONSENT_CANCELLED');
  request.cancel();await rejected;
  f.finishWindow();await tick();
  assert.equal(f.content, undefined);assert.equal(f.closed, 0);
});

test('cancelling during dialog open waits for mounting and releases the exact content once', async () => {
  const f = fixture({ pendingOpen: true });
  const request = f.request();
  const rejected = assert.rejects(request.result, error => error.code === 'LINE_CONSENT_CANCELLED');
  await tick();
  request.cancel();
  assert.equal(f.closed, 0);assert.equal(f.disposed, 0);
  f.finishOpen();await rejected;
  assert.equal(f.closed, 1);assert.equal(f.disposed, 1);
  assert.deepEqual(f.content.params.headers, []);
  f.content.params.complete(true);request.cancel();await tick();
  assert.equal(f.closed, 1);assert.equal(f.disposed, 1);
});

test('system dismissal returns denial and never treats page disappearance as approval', async () => {
  const f = fixture();
  const request = f.request();
  await tick();assert.equal(f.options.keyboardAvoidMode, KeyboardAvoidMode.NONE);
  f.options.onDidDisappear();assert.equal(await request.result, false);
  assert.equal(f.closed, 1);assert.equal(f.disposed, 1);
});

test('explicit permission approval resolves true after the dialog is released', async () => {
  const f = fixture(); const request = f.request();
  await tick(); f.content.params.complete(true);
  assert.equal(await request.result, true);
  assert.equal(f.closed, 1); assert.equal(f.disposed, 1);
});

test('consent help opens in the existing browser without authorization headers and returns to the same consent', async () => {
  const f = fixture(); const request = f.request(); await tick();
  const consent = f.content;
  const address = 'https://help.line.me/line/?contentId=200000394&utm_source=line';
  await consent.params.openBrowser(address);
  const browser = f.content;
  assert.notEqual(browser, consent);
  assert.equal(browser.params.url, address);
  assert.equal(browser.params.headers, undefined);
  assert.equal(browser.params.nativeAuth, undefined);
  await assert.rejects(browser.params.openMiniApp({ appId: 'unrelated', vendor: 'line',
    url: 'https://miniapp.line.me/unrelated' }), { code: 'NOT_SUPPORTED' });
  assert.equal(f.closed, 0);
  browser.params.close(); await tick();
  assert.equal(f.closed, 1);
  consent.params.complete(true);
  assert.equal(await request.result, true);
  assert.equal(f.closed, 2);
});

test('cancelling consent closes its help browser and prevents late browser requests', async () => {
  const f = fixture(); const request = f.request(); await tick();
  const consent = f.content;
  await assert.rejects(consent.params.openBrowser('javascript:alert(1)'), { code: 'INVALID_ARGUMENT' });
  assert.equal(f.contents.length, 1);
  await consent.params.openBrowser('https://help.line.me/line/');
  const rejected = assert.rejects(request.result, { code: 'LINE_CONSENT_CANCELLED' });
  request.cancel(); await rejected; await tick();
  assert.equal(f.closed, 2);
  assert.equal(f.disposed, 2);
  await assert.rejects(consent.params.openBrowser('https://help.line.me/line/'), { code: 'LINE_CONSENT_CANCELLED' });
  assert.equal(f.contents.length, 2);
});
