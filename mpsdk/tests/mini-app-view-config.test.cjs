const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

test('MiniAppView binds the session Web configuration before loading the entry URL', () => {
  const source = fs.readFileSync(path.join(__dirname, '../src/main/ets/web/MiniAppView.ets'), 'utf8');
  for (const token of [
    'this.session.info.isSyncLoad', 'this.session.info.isOpenDomStorage',
    'this.session.info.isOpenGeolocation', 'this.session.isWebWindowEnabled()',
    'mergeDocumentStartScripts', 'documentEndScripts', 'resolveUserAgent',
    '.onSslErrorEvent(', '.onSslErrorEventReceive('
  ]) {
    assert.ok(source.includes(token), `missing Web config binding: ${token}`);
  }
  const attachStart = source.indexOf('  private attach(): void {');
  const loadStart = source.indexOf('  private loadInitial(', attachStart);
  const attach = source.slice(attachStart, loadStart);
  assert.ok(attachStart >= 0 && loadStart > attachStart, 'view lifecycle methods must exist');
  assert.ok(attach.indexOf('setCustomUserAgent(userAgent)') < attach.indexOf('this.loadInitial('));
});

test('MiniAppView forwards navigation metadata to Session without vendor branches', () => {
  const source = fs.readFileSync(path.join(__dirname, '../src/main/ets/web/MiniAppView.ets'), 'utf8');
  const handler = source.slice(source.indexOf('.onLoadIntercept('), source.indexOf('.onSslErrorEvent('));
  for (const token of ['getRequestUrl()', 'isMainFrame()', 'getDocumentId()',
    'return this.session.interceptWebScheme(request)']) {
    assert.ok(handler.includes(token), `missing navigation wiring: ${token}`);
  }
  assert.equal(handler.includes('liff'), false);
});

test('MiniAppView omits absent native loadUrl headers and preserves supplied headers', () => {
  const source = fs.readFileSync(path.join(__dirname, '../src/main/ets/web/MiniAppView.ets'), 'utf8');
  const method = source.match(/  private loadInitial\([^)]*\): void \{([\s\S]*?)\n  \}/);
  assert.ok(method, 'initial URL loading must have a testable boundary');
  const load = new Function('address', 'headers', 'SdkLogger', 'TAG', method[1]);
  const calls = [];
  const view = {
    session: { initialUrl: 'https://example.com/' },
    initialHeaders: undefined,
    controller: { loadUrl(...args) {
      if (args.length > 1 && !Array.isArray(args[1])) {
        throw new Error('Invalid input parameter');
      }
      calls.push(args);
    } }
  };
  const logger = { info() {} };
  load.call(view, view.session.initialUrl, view.initialHeaders, logger, 'WebView');
  assert.deepEqual(calls.pop(), [view.session.initialUrl]);
  view.initialHeaders = [{ headerKey: 'X-LINE-LIFF-TOKEN', headerValue: 'test-token' }];
  load.call(view, view.session.initialUrl, view.initialHeaders, logger, 'WebView');
  assert.deepEqual(calls.pop(), [view.session.initialUrl, view.initialHeaders]);
  view.initialHeaders = [];
  load.call(view, view.session.initialUrl, view.initialHeaders, logger, 'WebView');
  assert.deepEqual(calls.pop(), [view.session.initialUrl]);
});
