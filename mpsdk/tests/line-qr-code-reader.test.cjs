const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const tick = () => new Promise(resolve => setImmediate(resolve));

function fixture(mode, openMiniApp = async () => {}, viaBinding = false) {
  const copies = [], opened = [], shown = [], miniApps = [], toasts = [];
  const load = createLoader(undefined, undefined, {
    async getLastWindow() {
      return { getUIContext: () => ({ getPromptAction: () => ({ showToast: message => toasts.push(message) }) }) };
    }
  }, undefined, undefined, undefined, {
    '@kit.ArkTS': { url: { URL } },
    '@kit.BasicServicesKit': { pasteboard: {
      MIMETYPE_TEXT_PLAIN: 'text/plain', createData: (_type, text) => text,
      getSystemPasteboard: () => ({ setData: async text => copies.push(text) })
    } }
  });
  const Reader = load('main/ets/capabilities/media/CodeReaderTools').CodeReaderTools;
  let resolveScan, rejectScan, resolveDialog, scans = 0;
  Reader.prototype.read = () => { scans++; return new Promise((resolve, reject) => {
    resolveScan = resolve; rejectScan = reject;
  }); };
  const { LineScanResultDialogHost } = load('main/ets/vendors/line/scan/LineScanResultDialogHost');
  const { LineScanResultAction: A } = load('main/ets/vendors/line/scan/LineScanResultTypes');
  LineScanResultDialogHost.prototype.show = value => {
    shown.push(value); return new Promise(resolve => { resolveDialog = resolve; });
  };
  LineScanResultDialogHost.prototype.dismiss = () => resolveDialog?.(A.CLOSE);
  let browserDismissed = 0, browserDisposed = 0;
  const { LineBrowserHost } = load('main/ets/vendors/line/browser/LineBrowserHost');
  LineBrowserHost.prototype.open = async address => { opened.push(address); };
  LineBrowserHost.prototype.dismissAll = () => { browserDismissed++; };
  LineBrowserHost.prototype.dispose = () => { browserDisposed++; };
  const { LineQrCodeReaderSchemeHandler } = load('main/ets/vendors/line/scheme/LineQrCodeReaderSchemeHandler');
  const ports = {
    isCurrent: request => foreground && request.documentId === documentId,
    openMiniApp: async app => { miniApps.push(app); await openMiniApp(app); }
  };
  let handler;
  if (viaBinding) {
    const { LineBinding } = load('main/ets/vendors/line/LineVendor');
    const session = { id: 'qr-mode-test', uiAbilityContext: {},
      getAdapter: () => ({ mode }), getDocumentId: () => documentId, isClosed: () => false,
      lifecycle: { isForeground: () => foreground }, requestOpenMiniApp: ports.openMiniApp };
    handler = LineBinding.prototype.createWebSchemeHandlers.call({ session, disposed: false })
      .find(item => item.id === 'line.qrcode.reader');
    assert.ok(handler);
  } else {
    handler = new LineQrCodeReaderSchemeHandler({}, ports, mode);
  }
  const { WebSchemeDispatcher } = load('main/ets/web/scheme/WebSchemeDispatcher');
  const { WebSchemeDecision: D } = load('main/ets/web/scheme/WebSchemeTypes');
  const dispatcher = new WebSchemeDispatcher([handler]);
  let documentId = 1, foreground = true;
  return { A, D, dispatcher, opened, shown, copies, miniApps, toasts, get scans() { return scans; },
    get browserDismissed() { return browserDismissed; }, get browserDisposed() { return browserDisposed; },
    dispatch: (url = 'https://line.me/R/nv/QRCodeReader', isMainFrame = true) =>
      dispatcher.dispatch({ url, isMainFrame, documentId }),
    scan: value => resolveScan(value), failScan: () => rejectScan(new (load('main/ets/core/MiniAppError').MiniAppError)(
      'USER_CANCELLED', 'cancelled')), choose: action => resolveDialog(action),
    navigate: () => { documentId++; dispatcher.reset(); }, hide: () => { foreground = false; } };
}

test('QRCodeReader matches only its two entry forms and refuses subframes or duplicate scans', async () => {
  const f = fixture();
  for (const url of ['https://evil.test/R/nv/QRCodeReader', 'https://line.me.evil/R/nv/QRCodeReader',
    'line://nv/QRCode', 'line://nv/QRCodeReader/extra', 'https://user@line.me/R/nv/QRCodeReader']) {
    assert.equal(f.dispatch(url), f.D.PASS, url);
  }
  assert.equal(f.dispatch(undefined, false), f.D.BLOCK);
  assert.equal(f.dispatch('LINE://nv/QRCodeReader/'), f.D.CONSUME);
  assert.equal(f.dispatch(), f.D.BLOCK);
  assert.equal(f.scans, 1);
  f.scan('https://example.test/path'); await tick();
  assert.deepEqual(f.opened, []);
  f.choose(f.A.OPEN); await tick();
  assert.deepEqual(f.opened, ['https://example.test/path']);
});

test('plain text and other schemes can be copied but are never opened', async () => {
  for (const value of ['hello\nworld', 'javascript:alert(1)', 'line://nv/chat', 'https://user:pass@example.test']) {
    const f = fixture(); f.dispatch(); f.scan(value); await tick();
    f.choose(f.A.COPY); await tick();
    assert.deepEqual(f.copies, [value]); assert.deepEqual(f.opened, []);
  }
});

test('navigation and disposal discard late scanner or dialog results', async () => {
  const f = fixture(); f.dispatch(); f.navigate(); f.scan('late'); await tick();
  assert.deepEqual(f.shown, []);
  f.dispatch(); f.scan('https://example.test'); await tick();
  f.dispatcher.dispose(); await tick();
  assert.deepEqual(f.opened, []); assert.deepEqual(f.copies, []);
});

test('cancelled scans allow retry without showing a result or opening a URL', async () => {
  const f = fixture(); f.dispatch(); f.failScan(); await tick();
  assert.deepEqual(f.shown, []); assert.deepEqual(f.opened, []);
  assert.equal(f.dispatch(), f.D.CONSUME);
  f.scan('text'); await tick(); f.choose(f.A.CLOSE); await tick();
  assert.deepEqual(f.copies, []);
});

test('scanner owner dismisses result browsers on navigation and disposes them on exit', () => {
  const f = fixture();
  f.navigate(); assert.equal(f.browserDismissed, 1);
  f.dispatcher.dispose(); assert.equal(f.browserDisposed, 1);
});

test('CLIENT and unspecified modes retain the original LINE deep-link text result', async () => {
  for (const mode of ['client', undefined]) {
    const f = fixture(mode); f.dispatch(); f.scan('line://app/123-App?x=1'); await tick();
    assert.deepEqual(f.miniApps, []);
    assert.deepEqual(f.shown, ['line://app/123-App?x=1']);
    f.choose(f.A.COPY); await tick();
    assert.deepEqual(f.copies, ['line://app/123-App?x=1']);
    assert.deepEqual(f.opened, []);
  }
});

test('WEB and WEB_HOOK extend valid LINE app links without rewriting query or fragment', async () => {
  const tail = '?liff.state=%3Fliff.utm_source%3Dline%26x%3D%252F&liff.source=lp_qr&liff.via=lp_qr#part';
  for (const mode of ['web', 'web_hook']) {
    const f = fixture(mode); f.dispatch(); f.scan('line://app/1657912723-mk7jvOME' + tail); await tick();
    assert.deepEqual(f.miniApps, [{ appId: '1657912723-mk7jvOME', vendor: 'line',
      url: 'https://liff.line.me/1657912723-mk7jvOME' + tail }]);
    assert.deepEqual(f.shown, []); assert.deepEqual(f.opened, []); assert.deepEqual(f.copies, []);
  }
});

test('Binding passes the current Session mode to the QR reader', async () => {
  for (const mode of ['client', 'web', 'web_hook']) {
    const f = fixture(mode, undefined, true);
    f.dispatch(); f.scan('line://app/123-App'); await tick();
    if (mode === 'client') {
      assert.deepEqual(f.miniApps, []); assert.deepEqual(f.shown, ['line://app/123-App']);
      f.choose(f.A.CLOSE); await tick();
    } else {
      assert.equal(f.miniApps.length, 1); assert.deepEqual(f.shown, []);
    }
    f.dispatcher.dispose();
  }
});

test('all modes retain the original HTTP, text and invalid LINE result actions', async () => {
  for (const mode of ['client', 'web', 'web_hook']) {
    for (const value of ['hello', 'line://nv/chat', 'line://app/', 'line://app/a/b', 'line://app/%ZZ',
      'line://app/%2Fbad', 'line://app.evil/a', 'line://user@app/a', 'line://APP/a']) {
      const f = fixture(mode); f.dispatch(); f.scan(value); await tick();
      assert.deepEqual(f.miniApps, []); assert.deepEqual(f.shown, [value]);
      f.choose(f.A.COPY); await tick(); assert.deepEqual(f.copies, [value]);
    }
    const f = fixture(mode); f.dispatch(); f.scan('https://example.test/path'); await tick();
    assert.deepEqual(f.miniApps, []); assert.deepEqual(f.shown, ['https://example.test/path']);
    f.choose(f.A.OPEN); await tick(); assert.deepEqual(f.opened, ['https://example.test/path']);
    assert.equal(f.dispatch(), f.D.CONSUME); f.failScan(); await tick();
    assert.deepEqual(f.miniApps, []); assert.deepEqual(f.toasts, []);
    assert.deepEqual(f.shown, ['https://example.test/path']);
  }
});

test('web extensions discard scanner results after navigation, backgrounding or disposal', async () => {
  for (const mode of ['web', 'web_hook']) {
    for (const close of [f => f.navigate(), f => f.hide(), f => f.dispatcher.dispose()]) {
      const f = fixture(mode); f.dispatch(); close(f); f.scan('line://app/123-App'); await tick();
      assert.deepEqual(f.miniApps, []); assert.deepEqual(f.shown, []);
    }
  }
});

test('web extension failures keep retry and suppress old-page error UI', async () => {
  for (const mode of ['web', 'web_hook']) {
    let rejectOpen;
    const f = fixture(mode, () => new Promise((_resolve, reject) => { rejectOpen = reject; }));
    f.dispatch(); f.scan('line://app/123-App'); await tick();
    assert.equal(f.dispatch(), f.D.BLOCK); assert.equal(f.miniApps.length, 1);
    f.navigate(); rejectOpen(Error('old page')); await tick(); assert.deepEqual(f.toasts, []);
    assert.equal(f.dispatch(), f.D.CONSUME);
    f.scan('line://app/456-App'); await tick(); rejectOpen(Error('host rejected')); await tick();
    assert.equal(f.toasts.length, 1);
    assert.equal(f.toasts[0].message.name, 'app.string.mp_line_scan_result_failed');
    assert.equal(f.dispatch(), f.D.CONSUME); f.failScan(); await tick();
  }
});
