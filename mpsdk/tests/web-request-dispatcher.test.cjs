const test = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
global.WebResourceResponse = class WebResourceResponse {};
function setup() {
  const load = createLoader();
  return { ...load('main/ets/web/request/WebRequestDispatcher'), ...load('main/ets/web/request/WebRequestTypes'), load };
}
const request = { url: 'https://example.test/resource', isMainFrame: false };
const handler = (id, handle, extra = {}) => ({ id, supports: () => true, handle, ...extra });
test('ordered continuation, response replacement and explicit PASS semantics', () => {
  const { WebRequestDispatcher: Dispatcher, WebRequestDecision: D } = setup();
  assert.equal(new Dispatcher([]).dispatch(request), D.PASS);
  const events = [], response = new WebResourceResponse();
  const dispatcher = new Dispatcher([
    handler('skip', () => { throw Error(); }, { supports: () => false }),
    handler('outer', (value, chain) => { assert.equal(value, request); events.push('before'); chain.proceed(); events.push('after'); return D.respond(response); }),
    handler('inner', () => { events.push('inner'); return D.PASS; }),
    handler('unused', () => { throw Error(); })
  ]);
  assert.equal(dispatcher.dispatch(request).response, response);
  assert.deepEqual(events, ['before', 'inner', 'after']);
});
test('exceptions, duplicate and saved continuation block', () => {
  const { WebRequestDispatcher: Dispatcher, WebRequestDecision: D } = setup();
  for (const handle of [() => { throw Error(); }, (_, chain) => { chain.proceed(); return chain.proceed(); }]) {
    assert.equal(new Dispatcher([handler('bad', handle)]).dispatch(request), D.BLOCK);
  }
  let saved;
  new Dispatcher([handler('save', (_, chain) => { saved = chain; return D.PASS; })]).dispatch(request);
  assert.equal(saved.proceed(), D.BLOCK);
});
test('reset invalidates dispatch and dispose is idempotent and continues after failure', () => {
  const { WebRequestDispatcher: Dispatcher, WebRequestDecision: D } = setup();
  const events = []; let dispatcher;
  dispatcher = new Dispatcher([
    handler('reset', () => { dispatcher.reset(); return D.PASS; }, {
      reset() { events.push('reset'); }, dispose() { events.push('first'); throw Error(); }
    }), handler('last', () => D.PASS, { dispose() { events.push('last'); } })
  ]);
  assert.equal(dispatcher.dispatch(request), D.BLOCK);
  dispatcher.dispose(); dispatcher.dispose();
  assert.equal(dispatcher.dispatch(request), D.BLOCK);
  assert.deepEqual(events, ['reset', 'first', 'last']);
});
test('invalid registration releases failed batch once', () => {
  const { WebRequestDispatcher: Dispatcher, WebRequestDecision: D } = setup();
  let disposed = 0;
  const first = handler('same', () => D.PASS, { dispose() { disposed++; } });
  assert.throws(() => new Dispatcher([first, first])); assert.equal(disposed, 1);
});

test('session runs SDK before host, guards stale documents and releases each mount', () => {
  const { load, WebRequestDecision: D } = setup();
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const calls = []; let factories = 0;
  function create(id, fail = false) {
    return new MiniAppSession(id, {
      info: { appId: 'same', vendor: 'test', url: 'https://example.test/' },
      adapter: { vendorId: 'test' }, swipeBackController: { dispose() {} },
      vendor: { vendorId: 'test', createBinding: () => ({
        createWebRequestHandlers: () => [handler('sdk', (_, chain) => {
          calls.push(id + ':sdk'); return chain.proceed();
        }, { dispose() { calls.push(id + ':sdk.dispose'); } })],
        onDocumentChanged() {}, dispose() { calls.push(id + ':binding.dispose'); }
      }) },
      createWebRequestHandlers: () => {
        factories++;
        if (fail) throw Error('factory failed');
        return [handler('host', () => {
          calls.push(id + ':host'); return D.respond(new WebResourceResponse());
        }, { reset() { calls.push(id + ':reset'); }, dispose() { calls.push(id + ':dispose'); } })];
      }
    }, {});
  }
  const a = create('a'), b = create('b');
  const dispatch = (session, documentId = session.getDocumentId()) => session.interceptWebRequest({ ...request, documentId });
  assert.equal(dispatch(a), D.BLOCK);
  for (const session of [a, b]) {
    session.attach({ evaluate: async () => '' }); session.beginDocument('https://example.test/');
  }
  calls.length = 0;
  assert.ok(dispatch(a).response); assert.deepEqual(calls, ['a:sdk', 'a:host']);
  a.beginDocument('https://example.test/next'); assert.equal(dispatch(a, 1), D.BLOCK);
  a.close(); assert.equal(dispatch(a), D.BLOCK); assert.ok(dispatch(b).response);
  assert.equal(factories, 2); assert.ok(calls.includes('a:reset')); assert.ok(calls.includes('a:dispose'));
  b.close(); calls.length = 0;
  assert.throws(() => create('failure', true));
  assert.deepEqual(calls, ['failure:sdk.dispose', 'failure:binding.dispose']);
});
