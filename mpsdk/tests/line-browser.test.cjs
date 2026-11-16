const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const tick = () => new Promise(resolve => setImmediate(resolve));
global.DialogAlignment = { Center: 0 };

function fixture({ pendingWindow = false, pendingOpen = false, failOpen = false, failClose = false,
  openMiniApp = async () => {}, adapter, lifecycle } = {}) {
  const contents = [], options = [], closed = [], disposed = [];
  let releaseWindow, releaseOpen;
  const prompt = {
    async openCustomDialog(content, option) {
      options.push(option);
      if (pendingOpen) await new Promise(resolve => { releaseOpen = resolve; });
      if (failOpen) throw new Error('platform open failed');
    },
    async closeCustomDialog(content) { closed.push(content); if (failClose) throw new Error('close failed'); }
  };
  const hostWindow = { getUIContext: () => ({ getPromptAction: () => prompt }) };
  class Content {
    constructor(_context, _builder, params) { this.params = params; contents.push(this); }
    dispose() { disposed.push(this); }
  }
  const load = createLoader(undefined, undefined,
    { getLastWindow: () => pendingWindow ? new Promise(resolve => { releaseWindow = resolve; }) : Promise.resolve(hostWindow) },
    undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } }, '@kit.ArkUI': { ComponentContent: Content },
      '@kit.ArkWeb': { webview: { WebviewController: class {} } } });
  const { LineBrowserHost } = load('main/ets/vendors/line/browser/LineBrowserHost');
  return { host: new LineBrowserHost({}, openMiniApp, adapter, lifecycle), contents, options, closed, disposed, load,
    finishWindow: () => releaseWindow(hostWindow), finishOpen: () => releaseOpen() };
}

test('native popup reserves its controller synchronously and presents the same window without native auth', async () => {
  const f = fixture();
  const popup = f.host.reserveWindow('');
  assert.ok(popup.controller);
  assert.equal(f.contents.length, 0);
  await popup.show();
  assert.equal(f.contents.length, 1);
  assert.equal(f.contents[0].params.popupController, popup.controller);
  assert.equal(f.contents[0].params.url, '');
  assert.equal(f.contents[0].params.nativeAuth, undefined);
  await assert.rejects(popup.show());
  popup.close(); popup.close(); await tick();
  assert.equal(f.disposed.length, 1);
});

test('native popup cancellation before show and during mounting cannot leave a late window', async () => {
  const cancelled = fixture(); const first = cancelled.host.reserveWindow('about:blank');
  cancelled.host.dismissAll();
  await assert.rejects(first.show(), { code: 'DOCUMENT_CHANGED' });
  assert.equal(cancelled.contents.length, 0);
  const f = fixture({ pendingWindow: true }); const popup = f.host.reserveWindow('');
  const pending = assert.rejects(popup.show(), { code: 'DOCUMENT_CHANGED' });
  f.host.dismissAll(); f.finishWindow(); await pending;
  assert.equal(f.contents.length, 0);
  assert.throws(() => f.host.reserveWindow('file:///a'), { code: 'INVALID_ARGUMENT' });
});

test('browser open resolves on presentation and each content closes independently', async () => {
  const f = fixture();
  await f.host.open('https://example.test/one');
  await f.host.open('https://example.test/two');
  assert.equal(f.contents.length, 2);
  assert.equal(f.options[0].keyboardAvoidMode, KeyboardAvoidMode.NONE);
  assert.deepEqual(Object.keys(f.contents[0].params).sort(), ['close', 'hostWindow', 'isAvailable', 'openMiniApp', 'url']);
  assert.equal(f.contents[0].params.url, 'https://example.test/one');
  f.contents[0].params.close(); await tick();
  assert.deepEqual(f.closed, [f.contents[0]]);
  f.contents[0].params.close(); f.options[0].onDidDisappear(); await tick();
  assert.equal(f.closed.length, 1); assert.equal(f.disposed.length, 1);
  f.host.dispose(); await tick();
  assert.deepEqual(f.closed, f.contents); assert.deepEqual(f.disposed, f.contents);
});

test('browser entry stops OAuth continuation as soon as release begins', async () => {
  const { LineAdapter } = createLoader()('main/ets/vendors/line/LineAdapter');
  const adapter = new LineAdapter({ mode: 'client', account: {} });
  const lifecycle = { isForeground: () => true };
  const f = fixture({ adapter, lifecycle });
  await f.host.open('https://shop.example/start');
  const params = f.contents[0].params;
  assert.equal(params.nativeAuth.adapter, adapter);
  assert.equal(params.nativeAuth.lifecycle, lifecycle);
  assert.ok(params.nativeAuth.consent);
  assert.equal(params.isAvailable(), true);
  params.close();
  assert.equal(params.isAvailable(), false);
  await tick(); assert.equal(f.closed.length, 1);
});

test('dispose before window arrival prevents late mounting', async () => {
  const f = fixture({ pendingWindow: true });
  const pending = assert.rejects(f.host.open('https://example.test'), { code: 'SESSION_CLOSED' });
  f.host.dispose(); f.finishWindow(); await pending;
  assert.equal(f.contents.length, 0);
  await assert.rejects(f.host.open('https://example.test'), { code: 'SESSION_CLOSED' });
});

test('document cleanup during mounting waits for attachment before releasing content', async () => {
  const f = fixture({ pendingOpen: true });
  const pending = assert.rejects(f.host.open('https://example.test'), { code: 'DOCUMENT_CHANGED' });
  await tick(); f.host.dismissAll();
  assert.equal(f.closed.length, 0); assert.equal(f.disposed.length, 0);
  f.finishOpen(); await pending; await tick();
  assert.equal(f.closed.length, 1); assert.equal(f.disposed.length, 1);
});

test('failed open disposes content and failed close does not stop other cleanup', async () => {
  const failed = fixture({ failOpen: true });
  await assert.rejects(failed.host.open('https://example.test'), { code: 'LINE_BROWSER_FAILED' });
  assert.equal(failed.disposed.length, 1); assert.equal(failed.closed.length, 0);
  const f = fixture({ failClose: true });
  await f.host.open('https://example.test/a'); await f.host.open('https://example.test/b');
  f.host.dispose(); f.host.dispose(); await tick();
  assert.equal(f.closed.length, 2); assert.equal(f.disposed.length, 2);
});

test('web URL validation blocks non-web, credentialed and malformed addresses before mounting', async () => {
  const f = fixture();
  const { validateLineBrowserUrl } = f.load('main/ets/vendors/line/browser/LineBrowserUrl');
  for (const value of ['file:///a', 'javascript:alert(1)', 'tel:+123', 'mailto:a@b', 'data:text/html,x',
    'https://user:pass@example.test', 'https://a b', ' https://example.test', 'https:example.test', '']) {
    assert.throws(() => validateLineBrowserUrl(value), { code: 'INVALID_ARGUMENT' });
    await assert.rejects(f.host.open(value), { code: 'INVALID_ARGUMENT' });
  }
  assert.equal(f.contents.length, 0);
  assert.equal(validateLineBrowserUrl('https://example.test/a?x=1#f').hostname, 'example.test');
});

test('browser forwards through its owner and closes only after host acceptance', async () => {
  let finish; const calls = [];
  const f = fixture({ openMiniApp: app => { calls.push(app); return new Promise(resolve => { finish = resolve; }); } });
  await f.host.open('https://example.test');
  const target = { appId: '123-App', vendor: 'line', url: 'https://liff.line.me/123-App?liff.source=lp_link' };
  const pending = f.contents[0].params.openMiniApp(target);
  assert.deepEqual(calls, [target]); assert.equal(f.closed.length, 0);
  finish(); await pending;
  assert.equal(f.closed.length, 1); assert.equal(f.disposed.length, 1);
  await assert.rejects(f.contents[0].params.openMiniApp(target)); assert.equal(calls.length, 1);
});

test('rejected host launch keeps the browser available and closed entries cannot forward', async () => {
  let calls = 0;
  const f = fixture({ async openMiniApp() { calls++; throw Error('rejected'); } });
  await f.host.open('https://example.test');
  const target = { appId: '123-App', vendor: 'line', url: 'https://liff.line.me/123-App' };
  await assert.rejects(f.contents[0].params.openMiniApp(target));
  assert.equal(f.closed.length, 0);
  f.host.dispose(); await tick();
  await assert.rejects(f.contents[0].params.openMiniApp(target)); assert.equal(calls, 1);
});

test('source document cleanup closes a pending browser and prevents retries from a new document', async () => {
  let reject; let calls = 0;
  const f = fixture({ openMiniApp: () => { calls++; return new Promise((_resolve, fail) => { reject = fail; }); } });
  await f.host.open('https://example.test');
  const target = { appId: '123-App', vendor: 'line', url: 'https://liff.line.me/123-App' };
  const pending = f.contents[0].params.openMiniApp(target);
  f.host.dismissAll(); await tick();
  assert.equal(f.closed.length, 1);
  reject(Error('issuance failed')); await assert.rejects(pending);
  await assert.rejects(f.contents[0].params.openMiniApp(target), { code: 'DOCUMENT_CHANGED' });
  assert.equal(calls, 1);
  f.host.dismissAll(); f.host.dispose(); await tick();
  assert.equal(f.closed.length, 1); assert.equal(f.disposed.length, 1);
});

test('self navigation document invalidation closes the originating browser without changing the error', async () => {
  const f = fixture({ async openMiniApp() {
    f.host.dismissAll();
    const { MiniAppError } = f.load('main/ets/core/MiniAppError');
    throw new MiniAppError('DOCUMENT_CHANGED', 'Source document changed after host acceptance');
  } });
  await f.host.open('https://example.test');
  await assert.rejects(f.contents[0].params.openMiniApp({ appId: '123-App', vendor: 'line',
    url: 'https://liff.line.me/123-App' }), { code: 'DOCUMENT_CHANGED' });
  assert.equal(f.closed.length, 1); assert.equal(f.disposed.length, 1);
});

test('browser owner cleanup cannot leave an old browser forwarding through a replacement document', async () => {
  let reject, calls = 0;
  const f = fixture({ openMiniApp: () => { calls++; return new Promise((_resolve, fail) => { reject = fail; }); } });
  const { LineOpenWindowHandler } = f.load('main/ets/vendors/line/handlers/LineOpenWindowHandler');
  let document = 1;
  const handler = new LineOpenWindowHandler({
    uiAbilityContext: {}, getDocumentId: () => document
  }, f.host);
  await handler.handle({ url: 'https://example.test/' }, {});
  const params = f.contents[0].params;
  const target = { appId: 'app', vendor: 'line', url: 'https://liff.line.me/app' };
  const pending = params.openMiniApp(target);
  f.host.dismissAll(); document++;
  reject(Error('host failure')); await assert.rejects(pending); await tick();
  assert.equal(f.closed.length, 1);
  document++;
  await assert.rejects(params.openMiniApp(target), { code: 'DOCUMENT_CHANGED' });
  assert.equal(calls, 1);
  handler.dispose(); f.host.dispose(); await tick(); assert.equal(f.disposed.length, 1);
});


test('WEB adapter does not enable native OAuth in the browser', async () => {
  const { LineAdapter } = createLoader()('main/ets/vendors/line/LineAdapter');
  const f = fixture({ adapter: new LineAdapter({ mode: 'web' }), lifecycle: { isForeground: () => true } });
  await f.host.open('https://shop.example/start');
  assert.equal(f.contents[0].params.nativeAuth, undefined); f.host.dispose(); await tick();
});
