const { applicationLifecycle } = require('./application-lifecycle.cjs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function fixture(onOpenMiniApp) {
  const load = createLoader();
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const session = new MiniAppSession('source', {
    info: { appId: 'source', vendor: 'test', url: 'https://example.com' },
    vendor: { vendorId: 'test', createBinding() { return { injections: [], scripts: [], onDocumentChanged() {}, dispose() {} }; } },
    adapter: {}, swipeBackController: { dispose() {} }, onOpenMiniApp
  }, {});
  const host = applicationLifecycle(load);
  host.onAbilityCreate({ context: session.uiAbilityContext });
  host.onAbilityForeground({ context: session.uiAbilityContext });
  session.attach({ evaluate: async () => '', pauseAllMedia() {} });
  return session;
}

test('session forwards an independent app snapshot without changing its own identity', async () => {
  const received = [];
  const source = fixture(async app => { received.push(app); });
  const target = { appId: 'target', vendor: 'line', url: 'https://liff.line.me/target', jsOnDocStartRules: ['https://x/*'] };
  await source.requestOpenMiniApp(target);
  target.jsOnDocStartRules.push('changed'); target.appId = 'changed';
  assert.equal(received[0].appId, 'target');
  assert.deepEqual(received[0].jsOnDocStartRules, ['https://x/*']);
  assert.equal(source.appId, 'source'); assert.ok(source.getBinding());
  source.close();
  assert.equal(source.descriptor.onOpenMiniApp, undefined, 'closed descriptor must not retain the host closure');
});

test('missing callback, closed session and navigation during host work are distinct failures', async () => {
  const app = { appId: 'target', vendor: 'line', url: 'https://liff.line.me/target' };
  const missing = fixture();
  await assert.rejects(missing.requestOpenMiniApp(app), { code: 'NOT_SUPPORTED' }); missing.close();
  let finish;
  const source = fixture(() => new Promise(resolve => { finish = resolve; }));
  const pending = source.requestOpenMiniApp(app);
  source.beginDocument('https://example.com/next'); finish();
  await assert.rejects(pending, { code: 'DOCUMENT_CHANGED' });
  source.close();
  await assert.rejects(source.requestOpenMiniApp(app), { code: 'SESSION_CLOSED' });
});

test('real container setup forwards its own event through SDK options into each session', async () => {
  const fs = require('node:fs'); const path = require('node:path');
  const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
  const source = fs.readFileSync(path.join(__dirname, '../src/main/ets/web/MiniAppContainer.ets'), 'utf8');
  const parsed = ts.createSourceFile('MiniAppContainer.ts', source.replace('struct MiniAppContainer', 'class MiniAppContainer'),
    ts.ScriptTarget.ES2020, true);
  const declaration = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'MiniAppContainer');
  const method = declaration.members.find(node => ts.isMethodDeclaration(node) && node.name.text === 'aboutToAppear');
  assert.ok(method, 'extract actual container lifecycle by syntax rather than member order');
  const js = ts.transpileModule(`class Container { ${method.getText(parsed)} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const load = createLoader();
  const { MiniAppSDK } = load('main/ets/core/MiniAppSDK');
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const Container = new Function('MiniAppSDK', 'MiniAppError', 'SdkLogger', 'TAG', 'SESSION_CREATE_FAILED',
    js + ';return Container;')(MiniAppSDK, MiniAppError, { info() {} }, 'Container', 'SESSION_CREATE_FAILED');
  const calls = [];
  function mount(id) {
    const view = new Container();
    view.app = { appId: id, vendor: 'line', url: 'https://example.test/' };
    view.adapter = new LineAdapter({ mode: 'web' });
    view.getUIContext = () => ({ getHostContext: () => ({}) });
    view.onOpenMiniApp = async app => { calls.push([id, app.appId]); };
    view.reportError = error => { throw error; };
    view.aboutToAppear();
    const host = applicationLifecycle(load);
    host.onAbilityCreate({ context: view.session.uiAbilityContext });
    host.onAbilityForeground({ context: view.session.uiAbilityContext });
    view.session.attach({ evaluate: async () => '', pauseAllMedia() {} });
    return view;
  }
  const first = mount('first'), second = mount('second');
  const app = { appId: 'target', vendor: 'line', url: 'https://liff.line.me/target' };
  await first.session.requestOpenMiniApp(app); await second.session.requestOpenMiniApp(app);
  assert.deepEqual(calls, [['first', 'target'], ['second', 'target']]);
  first.session.close(); second.session.close();
});
