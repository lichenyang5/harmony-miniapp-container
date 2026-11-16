const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const { createLoader } = require('./sdk-loader.cjs');
function fixture(methodName = 'navigateTo') {
  const source = fs.readFileSync(path.join(__dirname, '../src/main/ets/web/MiniAppView.ets'), 'utf8');
  // Parse the component body as a class and locate the method by syntax structure.
  const parsed = ts.createSourceFile('view.ts', source.replace('export struct MiniAppView', 'export class MiniAppView'), ts.ScriptTarget.Latest, true);
  let method;
  function visit(node) {
    if (ts.isClassDeclaration(node) && node.name?.text === 'MiniAppView') {
      method = node.members.find(member => ts.isMethodDeclaration(member) && member.name?.getText(parsed) === methodName);
    }
    ts.forEachChild(node, visit);
  }
  visit(parsed); assert.ok(method);
  let helper, helpersFailure;
  function findHelper(node) {
    if (ts.isClassDeclaration(node) && node.name?.text === 'MiniAppView') helper = node.members.find(member => ts.isMethodDeclaration(member) && member.name?.getText(parsed) === 'loadPreparedRequest');
    if (ts.isClassDeclaration(node) && node.name?.text === 'MiniAppView') {
      const failure = node.members.find(member => ts.isMethodDeclaration(member) && member.name?.getText(parsed) === 'failLoad');
      if (failure) helpersFailure = failure;
    }
    ts.forEachChild(node, findHelper);
  }
  findHelper(parsed);
  const js = ts.transpileModule('class View { ' + method.getText(parsed) + helper.getText(parsed) + helpersFailure.getText(parsed) + ' }', { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  const { MiniAppError } = createLoader()('main/ets/core/MiniAppError');
  const View = new Function('MiniAppError', 'NOT_SUPPORTED', 'DOCUMENT_CHANGED', 'WEB_CONTAINER_FAILED', js + ';return View;')(MiniAppError, 'NOT_SUPPORTED', 'DOCUMENT_CHANGED', 'WEB_CONTAINER_FAILED');
  const view = new View(); view.foreground = true;
  view.scriptInstaller = { install: async () => {} };
  let document = 1; let resolve; let reject; let closed = false;
  const order = []; const loads = [];
  const binding = { prepareNavigation(url) { order.push(['prepare', url]); return new Promise((done, fail) => { resolve = done; reject = fail; }); } };
  view.session = { isClosed: () => closed, lifecycle: { isForeground: () => view.foreground }, beginDocument(url) { document++; order.push(['document', url]); }, getDocumentId: () => document,
    getBinding() { if (closed) throw new MiniAppError('SESSION_CLOSED', 'closed'); return binding; } };
  view.controller = { stop() { order.push(['stop']); } };
  view.mediaPermissions = { cancel() { order.push(['media']); } };
  view.geolocationPermissions = { cancel() { order.push(['geo']); } };
  view.loadInitial = (...args) => loads.push(args);
  return { view, order, loads, resolve: value => resolve(value), reject: error => reject(error), navigate() { document++; }, close() { closed = true; } };
}
test('navigation prepares successfully before replacing the old document and permissions', async () => {
  const f = fixture(); const address = 'https://liff.line.me/app?liff.state=next';
  const pending = f.view.navigateTo(address);
  assert.deepEqual(f.order, [['prepare', address]]);
  await assert.rejects(f.view.navigateTo(address), error => error.code === 'NOT_SUPPORTED');
  f.resolve({ url: 'https://issued.example/', headers: [{ name: 'token', value: 'issued' }] }); await pending;
  assert.deepEqual(f.order, [['prepare', address], ['stop'], ['document', ''], ['media'], ['geo']]);
  assert.deepEqual(f.loads, [['https://issued.example/', [{ headerKey: 'token', headerValue: 'issued' }]]]);
  assert.equal(f.view.navigating, false);
  assert.equal(f.view.initialLoadStarted, true);
});
test('navigation or close while preparing prevents a late issued page from loading', async () => {
  for (const action of ['navigate', 'close']) {
    const f = fixture(); const pending = f.view.navigateTo('https://liff.line.me/app');
    f[action](); f.resolve({ url: 'https://late.example/' });
    await assert.rejects(pending); assert.deepEqual(f.loads, []); assert.equal(f.view.navigating, false);
  }
});

test('vendors without navigation support reject before stopping or invalidating the current document', async () => {
  const f = fixture();
  f.view.session.getBinding = () => ({});
  await assert.rejects(f.view.navigateTo('https://example.com/'), error => error.code === 'NOT_SUPPORTED');
  assert.deepEqual(f.order, []);
  assert.deepEqual(f.loads, []);
});


test('initial hidden view delays preparation until first activation and starts only once', () => {
  const f = fixture('startInitialLoad'); let calls = 0;
  f.view.attached = true; f.view.foreground = false;
  f.view.session.getBinding = () => ({ prepareInitialLoad() {} });
  f.view.loadPrepared = () => { calls++; };
  f.view.startInitialLoad(); assert.equal(calls, 0);
  f.view.foreground = true;
  f.view.startInitialLoad(); f.view.startInitialLoad(); assert.equal(calls, 1);
});

test('activation during navigation cannot start the abandoned initial URL in parallel', () => {
  const f = fixture('startInitialLoad'); let calls = 0;
  f.view.attached = true; f.view.foreground = true; f.view.navigating = true;
  f.view.initialLoadStarted = false;
  f.view.session.getBinding = () => ({ prepareInitialLoad() {} });
  f.view.loadPrepared = () => { calls++; };
  f.view.startInitialLoad(); assert.equal(calls, 0);
  assert.equal(f.view.initialLoadStarted, false);
});

test('successful initial preparation after hiding cannot load a background document', async () => {
  const f = fixture('loadPrepared'); let finish, retries = 0;
  f.view.foreground = true;
  f.view.initialLoadStarted = true;
  f.view.session.getBinding = () => ({ prepareInitialLoad: () => new Promise(resolve => { finish = resolve; }) });
  f.view.startInitialLoad = () => { if (f.view.foreground) retries++; };
  const pending = f.view.loadPrepared();
  f.view.foreground = false;
  finish({ url: 'https://issued.example/' }); await pending;
  assert.deepEqual(f.loads, []);
  assert.equal(f.view.initialLoadStarted, false);
  assert.equal(f.view.preparingInitialLoad, false);
  assert.equal(retries, 0);
});

test('a genuine initial preparation error is reported even while the container is hidden', async () => {
  const f = fixture('loadPrepared'); let reject; const errors = [];
  f.view.session.getBinding = () => ({ prepareInitialLoad: () => new Promise((_resolve, fail) => { reject = fail; }) });
  f.view.release = () => { f.view.released = true; };
  f.view.onError = error => errors.push(error);
  const pending = f.view.loadPrepared();
  f.view.foreground = false;
  reject(Error('actual service failure')); await pending;
  assert.equal(f.view.released, true);
  assert.equal(errors[0].code, 'WEB_CONTAINER_FAILED');
  assert.equal(f.view.preparingInitialLoad, false);
});

test('returning to foreground consumes the prepared entry once without a second login', () => {
  const f = fixture('startInitialLoad'); let calls = 0;
  f.view.attached = true; f.view.foreground = false;
  f.view.pendingInitialLoad = { url: 'https://issued.example/', headers: [{ name: 'token', value: 'issued' }] };
  f.view.loadPrepared = () => { calls++; };
  f.view.startInitialLoad(); assert.deepEqual(f.loads, []);
  f.view.foreground = true; f.view.startInitialLoad(); f.view.startInitialLoad();
  assert.equal(calls, 0);
  assert.deepEqual(f.loads, [['https://issued.example/', [{ headerKey: 'token', headerValue: 'issued' }]]]);
  assert.equal(f.view.pendingInitialLoad, undefined);
});


test('failed resumed initial loading terminates the container and reports an error once', () => {
  for (const cached of [true, false]) {
    const f = fixture('startInitialLoad'); const errors = [];
    f.view.attached = true;
    f.view.pendingInitialLoad = cached ? { url: 'https://issued.example/' } : undefined;
    f.view.session.getBinding = () => ({});
    f.view.loadInitial = () => { throw Error('loadUrl failed'); };
    f.view.release = () => { f.view.released = true; };
    f.view.onError = error => errors.push(error);
    f.view.startInitialLoad(); f.view.startInitialLoad();
    assert.equal(f.view.released, true); assert.equal(errors.length, 1);
    assert.equal(errors[0].code, 'WEB_CONTAINER_FAILED');
  }
});


test('rejected preparation preserves the original document and allows a retry', async () => {
  const f = fixture();
  const pending = f.view.navigateTo('https://liff.line.me/other');
  f.reject(Error('authorization denied')); await assert.rejects(pending);
  assert.equal(f.view.session.getDocumentId(), 1);
  assert.deepEqual(f.order, [['prepare', 'https://liff.line.me/other']]);
  assert.deepEqual(f.loads, []); assert.equal(f.view.navigating, false);
  const next = f.view.navigateTo('https://liff.line.me/app');
  f.resolve({ url: 'https://issued.example/' }); await next;
  assert.equal(f.view.session.getDocumentId(), 2);
  assert.equal(f.loads.length, 1);
});


test('a platform failure during navigation commit reports a fatal error instead of leaving an inactive document', async () => {
  const f = fixture(); const errors = [];
  f.view.loadInitial = () => { throw Error('loadUrl failed'); };
  f.view.release = () => { f.view.released = true; };
  f.view.onError = error => errors.push(error.code);
  const pending = f.view.navigateTo('https://liff.line.me/app');
  f.resolve({ url: 'https://issued.example/' }); await assert.rejects(pending);
  assert.equal(f.view.released, true);
  assert.deepEqual(errors, ['WEB_CONTAINER_FAILED']);
});

test('navigation rejected by LINE leaves the original ready Bridge usable', async () => {
  const vm = require('node:vm');
  const { applicationLifecycle } = require('./application-lifecycle.cjs');
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } } });
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const session = new MiniAppSession('failed-navigation', {
    info: { vendor: 'line', appId: 'app', url: 'https://liff.line.me/app' },
    adapter: new LineAdapter(), vendor: new LineVendor(), swipeBackController: { dispose() {} }
  }, {});
  const host = applicationLifecycle(load);
  host.onAbilityCreate({ context: session.uiAbilityContext }); host.onAbilityForeground({ context: session.uiAbilityContext });
  const events = [], window = { _liff: {}, liff: { _dispatchEvent: value => events.push(JSON.parse(value)) } };
  session.attach({ evaluate: async script => { vm.runInNewContext(script, { window }); return ''; }, pauseAllMedia() {} });
  session.beginDocument(session.initialUrl); session.finishDocument(session.initialUrl);
  const document = session.getDocumentId(), f = fixture(); f.view.session = session;
  try {
    await assert.rejects(f.view.navigateTo('https://liff.line.me/other'));
    assert.equal(session.getDocumentId(), document);
    session.getBinding().injections[0].object.postMessage('unknown', '', 'after-failure', '{}');
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(events.some(event => event.callbackId === 'after-failure'), true);
    assert.deepEqual(f.order, []);
  } finally { session.close(); }
});
