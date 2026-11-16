const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { createTestSession } = require('./test-session.cjs');
const { applicationLifecycle } = require('./application-lifecycle.cjs');

function fixture(scan, host, sharedLoad) {
  let calls = 0;
  const load = sharedLoad || createLoader({}, {
    async startScanForResult() { calls++; return scan ? await scan() : { originalValue: 'raw-code' }; }
  }, { async getLastWindow() { return { isWindowShowing: () => true }; } });
  const lifecycle = applicationLifecycle(load);
  const sent = [];
  const context = createTestSession(load, { id: 'scan', host,
    onScript(script) {
      new Function('window', script)({ atomicBridge: { postResponse(id, event) { sent.push({ id, event }); } } });
    }
  });
  const binding = context.getBinding();
  const proxy = binding.injections[0].object;
  return { load, lifecycle, binding, context, sent, calls: () => calls,
    request() {
      return proxy.onInterceptRequest(JSON.stringify({
        type: 'vk-connect', handler: 'VKWebAppOpenCodeReader', params: { request_id: 42 }
      }), 'original-route');
    }
  };
}

async function flush() { for (let i = 0; i < 30; i++) await Promise.resolve(); }

test('Ability background blocks scan even when window reports showing; foreground retry succeeds', async () => {
  const f = fixture();
  const host = f.context.uiAbilityContext;
  f.lifecycle.onAbilityCreate({ context: host });
  f.lifecycle.onAbilityForeground({ context: host });
  f.lifecycle.onAbilityBackground({ context: host }); // before the first request creates the lazy reader
  try {
    f.request();
    await flush();
    assert.equal(f.calls(), 0);
    assert.deepEqual(f.sent, [{ id: 'original-route', event: {
      type: 'VKWebAppOpenCodeReaderFailed', data: { request_id: 42,
        error_type: 'client_error', error_data: { error_code: 9,
          error_reason: 'This action cannot be performed in the background' } }
    } }]);
    f.lifecycle.onAbilityForeground({ context: host });
    f.sent.length = 0;
    f.request();
    await flush();
    assert.equal(f.calls(), 1);
    assert.deepEqual(f.sent[0].event, { type: 'VKWebAppOpenCodeReaderResult',
      data: { code_data: 'raw-code', request_id: 42 } });
  } finally { f.context.close(); f.lifecycle.onAbilityDestroy({ context: host }); }
});

test('unregistered and destroyed hosts never default to foreground', async () => {
  const f = fixture();
  const host = f.context.uiAbilityContext;
  try {
    f.request();
    await flush();
    assert.equal(f.calls(), 0);
    assert.deepEqual(f.sent.pop().event.data.error_data, { error_code: 1, error_reason: 'Unknown error' });

    f.lifecycle.onAbilityCreate({ context: host });
    f.lifecycle.onAbilityForeground({ context: host });
    f.lifecycle.onAbilityDestroy({ context: host });
    f.lifecycle.onAbilityDestroy({ context: host });
    f.lifecycle.onAbilityForeground({ context: host }); // late callback must not resurrect the host
    const { MiniAppLifecycleState } = f.load('main/ets/core/lifecycle/MiniAppLifecycle');
    assert.equal(f.context.lifecycle.getState(), MiniAppLifecycleState.DESTROYED);
    assert.throws(() => f.context.getBinding(), { code: 'SESSION_CLOSED' });
    f.request(); // a queued invocation may still retain the removed proxy
    await flush();
    assert.equal(f.calls(), 0);
    assert.equal(f.sent.length, 0);
  } finally { f.context.close(); f.lifecycle.onAbilityDestroy({ context: host }); }
});

test('foreground scan failure is not misreported as background', async () => {
  const f = fixture(async () => { throw { code: 1000500001, message: 'open failed' }; });
  const host = f.context.uiAbilityContext;
  f.lifecycle.onAbilityCreate({ context: host });
  f.lifecycle.onAbilityForeground({ context: host });
  try {
    f.request();
    await flush();
    assert.equal(f.calls(), 1);
    assert.deepEqual(f.sent[0].event.data.error_data, { error_code: 1, error_reason: 'Unknown error' });
  } finally { f.context.close(); f.lifecycle.onAbilityDestroy({ context: host }); }
});

test('host states are isolated and closing a session preserves its siblings host state', async () => {
  const a = fixture();
  const b = fixture(undefined, undefined, a.load);
  const sibling = fixture(undefined, a.context.uiAbilityContext, a.load);
  const hostA = a.context.uiAbilityContext, hostB = b.context.uiAbilityContext;
  a.lifecycle.onAbilityCreate({ context: hostA });
  a.lifecycle.onAbilityCreate({ context: hostB });
  a.lifecycle.onAbilityForeground({ context: hostA });
  try {
    b.request();
    a.request();
    await flush();
    assert.equal(b.sent[0].event.data.error_data.error_code, 9);
    assert.equal(a.sent[0].event.data.code_data, 'raw-code');
    a.context.close();
    sibling.request();
    await flush();
    assert.equal(sibling.sent[0].event.data.code_data, 'raw-code');
    assert.equal(a.calls(), 2);
  } finally {
    a.context.close(); b.context.close(); sibling.context.close();
    a.lifecycle.onAbilityDestroy({ context: hostA }); a.lifecycle.onAbilityDestroy({ context: hostB });
  }
});

test('background transition does not release an active scan and navigation or close drops its result', async () => {
  for (const close of [false, true]) {
    let finish;
    const f = fixture(() => new Promise(resolve => { finish = resolve; }));
    const host = f.context.uiAbilityContext;
    f.lifecycle.onAbilityCreate({ context: host });
    f.lifecycle.onAbilityForeground({ context: host });
    f.request();
    await flush();
    f.lifecycle.onAbilityBackground({ context: host });
    f.request();
    await flush();
    assert.equal(f.sent.pop().event.data.error_data.error_code, 9);
    f.lifecycle.onAbilityForeground({ context: host });
    f.request();
    await flush();
    assert.equal(f.sent.pop().event.data.error_data.error_code, 1); // still busy
    assert.equal(f.calls(), 1);
    if (close) f.context.close();
    else f.context.beginDocument('https://vk.ru/app1?next');
    assert.equal(typeof finish, 'function');
    finish({ originalValue: 'late' });
    await flush();
    assert.equal(f.calls(), 1);
    assert.equal(f.sent.length, 0);
    f.context.close();
    f.lifecycle.onAbilityDestroy({ context: host });
  }
});
