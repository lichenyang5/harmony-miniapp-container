const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const { createLoader } = require('./sdk-loader.cjs');
const { applicationLifecycle } = require('./application-lifecycle.cjs');

test('closing during a foreground notification cannot reactivate the view or report a loading error', () => {
  const load = createLoader();
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  const { MiniAppLifecycleController } = load('main/ets/core/lifecycle/MiniAppLifecycleController');
  const { MiniAppLifecycleState } = load('main/ets/core/lifecycle/MiniAppLifecycle');
  const source = fs.readFileSync(path.join(__dirname, '../src/main/ets/web/MiniAppView.ets'), 'utf8');
  const parsed = ts.createSourceFile('view.ts', source.replace('export struct MiniAppView', 'export class MiniAppView'), ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'MiniAppView');
  const names = ['lifecycleChanged', 'startInitialLoad', 'failLoad'];
  const methods = names.map(name => {
    const method = declaration.members.find(node => ts.isMethodDeclaration(node) && node.name?.getText(parsed) === name);
    assert.ok(method); return method.getText(parsed);
  });
  const js = ts.transpileModule('class View {' + methods.join('\n') + '}', { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  const View = new Function('MiniAppLifecycleState', 'MiniAppError', 'WEB_CONTAINER_FAILED', 'SYSTEM_ERROR', 'TAG', 'SdkLogger',
    js + ';return View;')(MiniAppLifecycleState, MiniAppError, 'WEB_CONTAINER_FAILED', 'SYSTEM_ERROR', 'WebView', { warn() {} });
  const controller = new MiniAppLifecycleController(false);
  let session;
  controller.observe(change => { if (change.current === 'FOREGROUND') session.close(); });
  const context = {}, host = applicationLifecycle(load);
  host.onAbilityCreate({ context }); host.onAbilityForeground({ context });
  session = new MiniAppSession('reentrant-close', {
    info: { appId: 'app', vendor: 'test', url: 'https://example.test/' },
    vendor: { vendorId: 'test', createBinding: () => ({ injections: [], scripts: [], onDocumentChanged() {}, dispose() {} }) },
    adapter: {}, lifecycleController: controller, swipeBackController: { dispose() {} }
  }, context);
  session.attach({ evaluate: async () => '', pauseAllMedia() {} });
  const view = new View(); view.session = session; view.attached = true;
  let activated = 0, released = 0; const errors = [];
  view.controller = { onActive() { activated++; }, onInactive() {} };
  view.release = () => { if (!view.released) { view.released = true; released++; } };
  view.onError = error => errors.push(error.code);
  session.lifecycle.observe(change => view.lifecycleChanged(change.current));
  controller.activate();
  assert.equal(controller.getState(), 'DESTROYED');
  assert.equal(activated, 0);
  assert.equal(released, 1);
  assert.deepEqual(errors, []);
});
