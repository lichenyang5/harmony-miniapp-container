const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createLoader } = require('./sdk-loader.cjs');

function fixture() {
  const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
  const source = fs.readFileSync(path.join(__dirname, '../src/main/ets/web/MiniAppView.ets'), 'utf8');
  const parsed = ts.createSourceFile('MiniAppView.ts', source.replace('export struct MiniAppView', 'export class MiniAppView'),
    ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'MiniAppView');
  assert.ok(declaration);
  const methods = ['loadPrepared', 'loadPreparedRequest', 'failLoad', 'handleRenderExited'].map(name => {
    const method = declaration.members.find(node => ts.isMethodDeclaration(node) && node.name?.getText(parsed) === name);
    assert.ok(method, `${name} lifecycle boundary must exist`); return method.getText(parsed);
  });
  const js = ts.transpileModule('class View { '+methods.join('\n')+'\n}', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const { MiniAppError } = createLoader()('main/ets/core/MiniAppError');
  const View = new Function('SdkLogger', 'TAG', 'MiniAppError', 'WEB_CONTAINER_FAILED', 'WEB_RENDERER_EXITED',
    js+';return View;')({ info() {} }, 'WebView', MiniAppError, 'WEB_CONTAINER_FAILED', 'WEB_RENDERER_EXITED');
  const view = new View();let resolve;let reject;
  const errors = [];const loads = [];
  const binding = { scripts: [], prepareInitialLoad: () => new Promise((yes, no) => { resolve=yes;reject=no; }) };
  view.foreground = true;
  view.session = { lifecycle: { isForeground: () => view.foreground }, id: 'initial', getBinding: () => binding };
  view.scriptInstaller = { install: async () => {} };
  view.release = () => { view.released = true; };
  view.onError = error => errors.push(error);
  view.loadInitial = (...args) => loads.push(args);
  return { view, binding, errors, loads, resolve: value => resolve(value), reject: value => reject(value) };
}

test('initial issuance installs the resolved identity scripts before loading or caching the entry', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkUI': { FrameCallback: class {} } });
  const { WebDocumentScriptInstaller } = load('main/ets/web/WebDocumentScriptInstaller');
  const { createLineMstScript } = load('main/ets/vendors/line/script/LineMstScript');
  for (const background of [false, true]) {
    const f = fixture(), frames = [];
    f.view.documentStartScripts = [];
    f.view.scriptInstaller = new WebDocumentScriptInstaller({ runScopedTask: task => task(),
      postFrameCallback: frame => frames.push(frame) }, scripts => { f.view.documentStartScripts = scripts; });
    const pending = f.view.loadPrepared();
    f.binding.scripts = [createLineMstScript('resolved-id', 'challenge')];
    f.resolve({ url: 'https://app.example/' });
    for (let i = 0; i < 5 && frames.length === 0; i++) await new Promise(resolve => setImmediate(resolve));
    assert.equal(frames.length, 1);
    assert.deepEqual(f.loads, [], 'loadUrl must wait until script properties have been committed');
    assert.match(f.view.documentStartScripts[0].script, /LIFF_STORE:resolved-id:mstChallenge/);
    f.view.foreground = !background;
    frames[0].onIdle(1000000); await pending;
    if (background) {
      assert.deepEqual(f.loads, []);
      assert.ok(f.view.pendingInitialLoad);
      f.view.foreground = true;
      f.view.loadPreparedRequest(f.view.pendingInitialLoad);
    }
    assert.equal(f.loads.length, 1);
    f.view.scriptInstaller.dispose();
  }
});

test('renderer loss while preparing initial load preserves the session and loads the eventual issued URL', async () => {
  const f = fixture();const pending = f.view.loadPrepared();
  f.view.handleRenderExited();
  assert.equal(f.view.released, undefined);assert.deepEqual(f.errors, []);
  f.resolve({ url:'https://app.example/', headers:[{ name:'X-LINE-LIFF-TOKEN', value:'app-token' }] });
  await pending;
  assert.deepEqual(f.loads, [['https://app.example/', [{ headerKey:'X-LINE-LIFF-TOKEN', headerValue:'app-token' }]]]);
  f.view.handleRenderExited();
  assert.equal(f.view.released, true);assert.equal(f.errors[0].code, 'WEB_RENDERER_EXITED');
});

test('failed preparation still fails the container after an initial renderer exit', async () => {
  const f = fixture();const pending = f.view.loadPrepared();
  f.view.handleRenderExited();f.reject(new Error('preparation failed'));await pending;
  assert.equal(f.view.released, true);assert.equal(f.loads.length, 0);
  assert.equal(f.errors[0].code, 'WEB_CONTAINER_FAILED');
});
