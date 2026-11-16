const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
function fixture(info = {}, supported = true) {
  const load = createLoader();
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const opened = [];
  const binding = { injections: [], scripts: [], onDocumentChanged() {}, dispose() {} };
  if (supported) binding.onNewWindow = request => { opened.push(request); return { controller: {}, show: async () => {}, close() {} }; };
  const session = new MiniAppSession('new-window', {
    info: { appId: 'app', vendor: 'test', url: 'https://example.test/', ...info },
    vendor: { vendorId: 'test', createBinding: () => binding }, adapter: { vendorId: 'test' },
    swipeBackController: { dispose() {} }
  }, {});
  const request = () => ({ url: 'https://voiceapp-lab.com/', isUserTrigger: true, isAlert: false, documentId: session.getDocumentId() });
  const attach = () => { session.attach({ evaluate: async () => '' }); session.lifecycle.setHostForeground(true); session.beginDocument('https://example.test/'); };
  return { session, binding, opened, request, attach, load };
}
test('new-window capability defaults to Binding support and respects explicit overrides', async () => {
  for (const [info, supported, enabled] of [[{}, false, false], [{}, true, true], [{isOpenNewWindow:false}, true, false], [{isOpenNewWindow:true}, false, true]]) {
    const f = fixture(info, supported); assert.equal(f.session.isWebWindowEnabled(), enabled); f.attach();
    if (!enabled || !supported) assert.throws(() => f.session.openWebWindow(f.request()), { code: 'NOT_SUPPORTED' });
    f.session.close();
  }
});
test('Session forwards only current attached foreground requests and preserves original metadata', async () => {
  const f = fixture();
  assert.throws(() => f.session.openWebWindow(f.request()), { code: 'WEB_NOT_ATTACHED' });
  f.attach(); const request = f.request(); await f.session.openWebWindow(request);
  assert.deepEqual(f.opened, [request]);
  f.session.beginDocument('https://example.test/next');
  assert.throws(() => f.session.openWebWindow(request), { code: 'DOCUMENT_CHANGED' });
  f.session.lifecycle.setHostForeground(false);
  assert.throws(() => f.session.openWebWindow(f.request()), { code: 'NOT_SUPPORTED' });
  f.session.close(); assert.throws(() => f.session.openWebWindow(f.request()), { code: 'SESSION_CLOSED' });
});

test('LINE modes share one Binding browser with Bridge and isolate mounts and lifecycle', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } }, '@kit.ArkWeb': { webview: { WebviewController: class {} } } });
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineBrowserHost } = load('main/ets/vendors/line/browser/LineBrowserHost');
  const opened = [], dismissed = [], disposed = [];
  LineBrowserHost.prototype.open = async function(url) { opened.push([this, url]); };
  const reserve = LineBrowserHost.prototype.reserveWindow;
  LineBrowserHost.prototype.reserveWindow = function(url) { const result = reserve.call(this, url); opened.push([this, url]); return result; };
  LineBrowserHost.prototype.dismissAll = function() { dismissed.push(this); };
  LineBrowserHost.prototype.dispose = function() { disposed.push(this); };
  const sessions = [];
  for (const mode of ['web', 'web_hook', 'client']) {
    const session = new MiniAppSession(mode, {
      info: { appId: 'same', vendor: 'line', url: 'https://example.test/' },
      vendor: new LineVendor(), adapter: new LineAdapter({ mode }), swipeBackController: { dispose() {} }
    }, {});
    session.attach({ evaluate: async () => '' }); session.lifecycle.setHostForeground(true);
    session.beginDocument('https://example.test/');
    const req = { url: 'https://voiceapp-lab.com/', isUserTrigger: true, isAlert: false, documentId: session.getDocumentId() };
    assert.equal(session.isWebWindowEnabled(), true);
    await session.openWebWindow(req);
    const browser = opened.at(-1)[0];
    for (const url of ['javascript:alert(1)', 'file:///a', 'https://u:p@example.test']) {
      assert.throws(() => session.openWebWindow({ ...req, url }), { code: 'INVALID_ARGUMENT' });
    }
    assert.throws(() => session.openWebWindow({ ...req, isUserTrigger: false }), { code: 'NOT_SUPPORTED' });
    const before = opened.length;
    const binding = session.getBinding();
    await binding.registry.getHandler('openWindow').handle({ url: 'https://example.test/' }, {});
    assert.equal(opened.length, before + 1); assert.equal(opened.at(-1)[0], browser);
    const resets = dismissed.filter(item => item === browser).length; session.beginDocument('https://example.test/next');
    assert.equal(dismissed.filter(item => item === browser).length, resets + 1);
    sessions.push([session, browser]);
  }
  assert.equal(new Set(sessions.map(([,browser]) => browser)).size, 3);
  sessions[0][0].close(); assert.deepEqual(disposed.filter(item => sessions.some(([,browser]) => item === browser)), [sessions[0][1]]);
  sessions[1][0].close(); sessions[2][0].close(); assert.equal(disposed.filter(item => sessions.some(([,browser]) => item === browser)).length, 3);
});

test('real View binds exactly once before presentation and closes failed or cancelled windows', async () => {
  const fs = require('node:fs'), path = require('node:path');
  const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
  const source = fs.readFileSync(path.join(__dirname, '../src/main/ets/web/MiniAppView.ets'), 'utf8');
  const parsed = ts.createSourceFile('view.ts', source.replace('export struct MiniAppView', 'export class MiniAppView'), ts.ScriptTarget.Latest, true);
  const component = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'MiniAppView');
  const names = ['handleNewWindow', 'reportNewWindowFailure'];
  const methods = component.members.filter(node => ts.isMethodDeclaration(node) && names.includes(node.name.getText(parsed)));
  assert.equal(methods.length, 2);
  const js = ts.transpileModule('class View {' + methods.map(m => m.getText(parsed)).join('\n') + '}', { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  const warnings = [], events = [];
  const { MiniAppError } = createLoader()('main/ets/core/MiniAppError');
  const View = new Function('SdkLogger', 'MiniAppError', 'SYSTEM_ERROR', 'TAG', js + '; return View;')(
    { warn: (...args) => warnings.push(args) }, MiniAppError, 'SYSTEM_ERROR', 'WebView');
  const view = new View(); let doc = 7;
  const popup = { controller: {}, async show() { events.push('show'); throw new MiniAppError('DOCUMENT_CHANGED', 'private URL'); }, close() { events.push('close'); } };
  view.session = { id: 'test', getDocumentId: () => doc, openWebWindow(request) { events.push(['reserve', request]); return popup; } };
  const event = { targetUrl: '', isUserTrigger: true, isAlert: false,
    handler: { setWebController(value) { events.push(['confirm', value]); doc++; event.targetUrl = 'changed'; } } };
  view.handleNewWindow(event); await new Promise(setImmediate);
  assert.deepEqual(events, [['reserve', { url: '', isUserTrigger: true, isAlert: false, documentId: 7 }], ['confirm', popup.controller], 'show', 'close']);
  assert.equal(warnings[0][2].code, 'DOCUMENT_CHANGED');
  assert.equal(JSON.stringify(warnings).includes('private URL'), false);
  events.length = 0;
  event.handler.setWebController = () => { events.push('confirm failed'); throw Error(); };
  view.handleNewWindow(event); assert.equal(events.at(-1), 'close'); assert.equal(events.includes('show'), false);
  events.length = 0;
  view.session.openWebWindow = () => { throw new MiniAppError('NOT_SUPPORTED', 'disabled'); };
  event.handler.setWebController = value => events.push(['reject', value]);
  view.handleNewWindow(event); assert.deepEqual(events, [['reject', null]]);
});
