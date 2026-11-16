const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');
const flush = () => new Promise(resolve => setImmediate(resolve));

class TestLineHandler {
  constructor(context, type, handle) {
    this.context = context;
    this.type = type;
    this.handle = handle;
  }
  dispose() {}
}

function fixture() {
  const load = createLoader();
  const { LineBridgeProxy } = load('main/ets/vendors/line/LineBridgeProxy');
  const { LineEventRegistry } = load('main/ets/vendors/line/LineEventRegistry');
  const { LineBridgeError } = load('main/ets/vendors/line/LineBridgeError');
  let documentId = 1;
  let state = { liffId: 'app', featureToken: 'token' };
  const events = [];
  const window = { liff: { _dispatchEvent(value) {
    assert.equal(typeof value, 'string'); events.push(JSON.parse(value));
  } } };
  const session = {
    getDocumentId: () => documentId,
    async send(script) { vm.runInNewContext(script, { window }); return true; }
  };
  const registry = new LineEventRegistry(session);
  const proxy = new LineBridgeProxy(registry, session, { getAppState: () => state });
  return { proxy, registry, LineBridgeError, events, window, session,
    register(type, handle) { registry.initHandler([new TestLineHandler(session, type, handle)]); },
    clearState: () => { state = undefined; },
    nextPage: () => { documentId++; proxy.onDocumentChanged(); },
    ready: () => proxy.onPageFinished(documentId) };
}

test('handlers declare actions after reply submission without method-specific routing', async () => {
  const f = fixture(); f.ready();
  const order = [];
  let complete;
  f.session.send = () => {
    order.push('submit');
    return new Promise(resolve => { complete = resolve; });
  };
  f.register('custom', async (_params, context) => {
    context.afterReplySubmitted(() => order.push('after'));
    return {};
  });
  f.proxy.postMessage('custom', 'token', '1', '{}');
  await flush();
  assert.deepEqual(order, ['submit', 'after']);
  complete(true); await flush();
});

test('failed handlers and serialization never run their registered actions', async () => {
  const f = fixture(); f.ready();
  let actions = 0;
  f.register('failure', async (_params, context) => {
    context.afterReplySubmitted(() => actions++);
    throw new Error('failure');
  });
  f.register('invalidResult', async (_params, context) => {
    context.afterReplySubmitted(() => actions++);
    const cyclic = {}; cyclic.self = cyclic;
    return cyclic;
  });
  f.proxy.postMessage('failure', 'token', '1', '{}');
  f.proxy.postMessage('invalidResult', 'token', '2', '{}');
  await flush();
  assert.equal(f.events.length, 2);
  assert.equal(actions, 0);
});

test('after-reply actions are request-local and discarded after navigation', async () => {
  const f = fixture(); f.ready();
  const actions = [], pending = new Map();
  f.register('deferred', (params, context) => {
    context.afterReplySubmitted(() => actions.push(params.id));
    return new Promise(resolve => pending.set(params.id, resolve));
  });
  f.proxy.postMessage('deferred', 'token', '1', '{"id":1}');
  f.proxy.postMessage('deferred', 'token', '2', '{"id":2}');
  pending.get(2)({}); await flush();
  assert.deepEqual(actions, [2]);
  f.nextPage(); f.ready(); pending.get(1)({}); await flush();
  assert.deepEqual(actions, [2]);
  assert.equal(f.events.length, 1);
});

test('action failures cannot send a second reply; navigation discards remaining and late actions', async () => {
  const f = fixture(); f.ready();
  const actions = [];
  let savedContext;
  f.register('actions', async (_params, context) => {
    savedContext = context;
    context.afterReplySubmitted(() => { throw new Error('private failure'); });
    context.afterReplySubmitted(() => { actions.push('navigate'); f.nextPage(); });
    context.afterReplySubmitted(() => actions.push('stale'));
    return {};
  });
  f.proxy.postMessage('actions', 'token', '1', '{}'); await flush();
  assert.equal(f.events.length, 1);
  assert.deepEqual(f.events[0].data, {});
  assert.deepEqual(actions, ['navigate']);
  savedContext.afterReplySubmitted(() => actions.push('late'));
  savedContext.runAfterReplySubmitted(() => true);
  assert.deepEqual(actions, ['navigate']);
});

test('validateFeatureToken checks current app/token and disposal without coercion', () => {
  const f = fixture();
  assert.equal(f.proxy.validateFeatureToken('app', 'token'), true);
  assert.equal(f.proxy.validateFeatureToken('wrong', 'token'), false);
  assert.equal(f.proxy.validateFeatureToken('app', 'wrong'), false);
  assert.equal(f.proxy.validateFeatureToken(null, 'token'), false);
  assert.equal(f.proxy.validateFeatureToken('app', null), false);
  f.clearState();
  assert.equal(f.proxy.validateFeatureToken('app', 'token'), false);
  f.proxy.dispose();
  assert.equal(f.proxy.validateFeatureToken('app', 'token'), false);
});

test('concurrent callbacks remain correlated; late rejection and transport failure do not leak or retry', async () => {
  const f = fixture(); f.ready();
  const pending = new Map();
  f.register('parallel', params => new Promise((resolve, reject) => {
    pending.set(params.key, { resolve, reject });
  }));
  f.proxy.postMessage('parallel', 'token', 'one', '{"key":1}');
  f.proxy.postMessage('parallel', 'token', 'two', '{"key":2}');
  pending.get(2).resolve({ key: 2 }); pending.get(1).resolve({ key: 1 });
  await flush();
  assert.deepEqual(f.events.map(e => [e.callbackId, e.data.key]), [['two', 2], ['one', 1]]);
  f.proxy.postMessage('parallel', 'token', 'old', '{"key":3}');
  f.nextPage(); f.ready(); pending.get(3).reject(new Error('late private error'));
  await flush(); assert.equal(f.events.length, 2);
  let attempts = 0;
  f.session.send = async () => { attempts++; throw new Error('transport'); };
  f.proxy.postMessage('unknown', 'token', 'failed-delivery', '{}');
  await flush(); assert.equal(attempts, 1);
});

test('token error precedes routing; closeWindow is exempt; unknown and unregistered known methods reply', async () => {
  const f = fixture(); f.ready();
  f.proxy.postMessage('unknown', 'wrong', '1', '{}');
  f.proxy.postMessage('unknown', 'token', '2', '{}');
  f.proxy.postMessage('scanCode', 'token', '3', '{}');
  f.proxy.postMessage('openWindow', 'token', '4', '{}');
  f.register('closeWindow', async () => ({}));
  f.proxy.postMessage('closeWindow', 'wrong', '5', '{}');
  await flush();
  const byId = Object.fromEntries(f.events.map(event => [event.callbackId, event]));
  assert.equal(byId['1'].error.code, 'NO_AUTHORITY');
  assert.equal(byId['2'].error.code, 'INVALID_MESSAGE');
  assert.equal(byId['3'].error.code, 'PERMISSION_DENIED');
  assert.equal(byId['4'].error.code, 'PERMISSION_DENIED');
  assert.deepEqual(byId['5'].data, {});
  f.clearState();
  f.proxy.postMessage('unknown', 'anything', '6', '{}');
  await flush();
  assert.equal(f.events.at(-1).error.code, 'INVALID_MESSAGE'); // APK skips comparison without configured token.
});

test('dispatch preserves request IDs, escapes scripts and maps handler/serialization errors', async () => {
  const f = fixture(); f.ready();
  const value = '"\\\n\u2028\u2029';
  f.register('echo', async params => ({ value: params.value }));
  f.proxy.postMessage('echo', 'token', value, JSON.stringify({ value }));
  f.register('knownError', async () => { throw f.LineBridgeError.noAuthority(); });
  f.proxy.postMessage('knownError', 'token', 'known', '{}');
  f.register('failure', async () => { throw new Error('private token and backend data'); });
  f.proxy.postMessage('failure', 'token', 'failure', '{}');
  const cyclic = {}; cyclic.self = cyclic;
  f.register('cyclic', async () => cyclic);
  f.proxy.postMessage('cyclic', 'token', 'cyclic', '{}');
  f.register('empty', async params => params);
  f.proxy.postMessage('empty', 'token', 'empty', 'invalid json');
  f.proxy.postMessage('empty', 'token', null, '{}');
  await flush();
  assert.equal(f.events.length, 5);
  assert.deepEqual(f.events.find(e => e.type === 'echo'), { type: 'echo', callbackId: value, data: { value } });
  assert.equal(f.events.find(e => e.type === 'knownError').error.code, 'NO_AUTHORITY');
  for (const type of ['failure', 'cyclic']) {
    assert.deepEqual(f.events.find(e => e.type === type).error, { code: 'INTERNAL_ERROR', description: 'Internal error' });
  }
  assert.deepEqual(f.events.find(e => e.type === 'empty').data, {});
});

test('inactive pages, late results, disposal and disposed registry cannot deliver to another page/session', async () => {
  const a = fixture(); const b = fixture();
  let complete;
  a.register('slow', () => new Promise(resolve => { complete = resolve; }));
  a.proxy.postMessage('slow', 'token', 'inactive', '{}');
  assert.equal(complete, undefined);
  a.ready(); a.proxy.postMessage('slow', 'token', 'late', '{}');
  a.nextPage(); a.ready(); complete({ done: true });
  await flush(); assert.equal(a.events.length, 0);
  a.proxy.postMessage('slow', 'token', 'closed', '{}');
  a.proxy.dispose(); complete({ done: true });
  b.ready(); b.proxy.postMessage('unknown', 'token', 'other-session', '{}');
  await flush();
  assert.equal(a.events.length, 0); assert.equal(b.events.length, 1);
  b.registry.dispose(); b.proxy.postMessage('unknown', 'token', 'disposed', '{}');
  await flush(); assert.equal(b.events.length, 1);
});

test('hidden LINE document rejects handlers while preserving token validation and an accepted open', async () => {
  const f = fixture(); f.ready(); let active = true; let calls = 0; let finish;
  f.session.lifecycle = { isForeground: () => active };
  f.register('openWindow', async () => { calls++; return new Promise(resolve => { finish = resolve; }); });
  f.proxy.postMessage('openWindow', 'token', 'first', '{}'); await flush();
  active = false;
  f.proxy.postMessage('openWindow', 'token', 'hidden', '{}'); await flush();
  assert.equal(calls, 1);
  assert.equal(f.proxy.validateFeatureToken('app', 'token'), true);
  assert.equal(f.events[0].callbackId, 'hidden');
  assert.equal(f.events[0].error.code, 'PERMISSION_DENIED');
  finish({}); await flush();
  assert.equal(f.events[1].callbackId, 'first');
});
