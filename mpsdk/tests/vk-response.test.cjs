require('./mini-app-lifecycle.test.cjs');
require('./mini-app-session-lifecycle.test.cjs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
require('./line-ready.test.cjs');
require('./line-mst.test.cjs');
require('./line-subview-rpc.test.cjs');
require('./line-subview-presentation.test.cjs');
require('./line-subwindow.test.cjs');
require('./line-subwindow-result.test.cjs');
require('./line-dialog.test.cjs');
require('./line-dialog-layout.test.cjs');
require('./line-web-scheme.test.cjs');
require('./line-liff-scheme.test.cjs');
require('./line-consent-scheme.test.cjs');
require('./line-bridge-proxy.test.cjs');
require('./line-event-registry.test.cjs');
require('./line-close-window.test.cjs');
require('./line-open-window-forward.test.cjs');
require('./line-open-window-route.test.cjs');
require('./line-direct-transition.test.cjs');
require('./miniapp-open.test.cjs');
require('./mini-app-navigateTo.test.cjs');
require('./line-login-insets.test.cjs');
require('./line-login-input.test.cjs');
require('./mini-app-live-session.test.cjs');
require('./line-browser.test.cjs');
require('./line-browser-app-scheme.test.cjs');
require('./line-browser-view.test.cjs');
require('./line-scan-code.test.cjs');
const { createLoader } = require('./sdk-loader.cjs');
require('./navigation-back.test.cjs');
require('./web-scheme-dispatcher.test.cjs');
require('./web-scheme-session.test.cjs');
require('./download-file.test.cjs');
require('./agent-download-file.test.cjs');
const { createTestSession } = require('./test-session.cjs');
require('./code-reader-background.test.cjs');
require('./host-lifecycle.test.cjs');
require('./open-contacts.test.cjs');
require('./param-validation.test.cjs');
require('./supported-handlers.test.cjs');
require('./test-banner.test.cjs');
require('./test-native-ad.test.cjs');
require('./vk-close.test.cjs');
require('./mini-app-info-snapshot.test.cjs');
require('./mini-app-web-config.test.cjs');
require('./mini-app-view-config.test.cjs');
require('./mini-app-view-initial-renderer.test.cjs');
require('./vk-launch-params.test.cjs');
require('./web-media-permissions.test.cjs');
require('./session-media-permissions.test.cjs');
require('./web-geolocation-permissions.test.cjs');
require('./accelerometer.test.cjs');
require('./gyroscope.test.cjs');
require('./device-motion.test.cjs');
require('./vk-group-info.test.cjs');
const { applicationLifecycle } = require('./application-lifecycle.cjs');

test('event annotations retain object inference and reject invalid metadata types', () => {
  const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
  const path = require('node:path');
  const program = ts.createProgram([path.join(__dirname, 'types/vk-response.ts')], {
    strict: true, noEmit: true, target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS,
    experimentalDecorators: true, types: []
  });
  const diagnostics = ts.getPreEmitDiagnostics(program);
  assert.equal(diagnostics.length, 0, diagnostics.map(d => ts.flattenDiagnosticMessageText(d.messageText, '\n')).join('\n'));
});

test('existing ArkTS suites', async t => {
  const cases = [];
  const load = createLoader({
    describe: (_name, body) => body(),
    it: (name, _flags, body) => cases.push({ name, body }),
    expect: actual => ({
      assertTrue: () => assert.equal(actual, true), assertFalse: () => assert.equal(actual, false),
      assertEqual: expected => assert.equal(actual, expected),
      assertUndefined: () => assert.equal(actual, undefined),
      assertContain: expected => assert.ok(actual.includes(expected))
    })
  });
  load('test/List.test').default();
  for (const item of cases) await t.test(item.name, item.body);
});

async function flush() { for (let i = 0; i < 20; i++) await Promise.resolve(); }

function fixture(scan = {}) {
  const load = createLoader({}, scan);
  const sent = [];
  const context = createTestSession(load, { id: 'review',
    onScript(script) {
      new Function('window', script)({ atomicBridge: { postResponse(id, data) { sent.push({ id, data }); } } });
    }
  });
  const lifecycle = applicationLifecycle(load);
  lifecycle.onAbilityCreate({ context: context.uiAbilityContext });
  lifecycle.onAbilityForeground({ context: context.uiAbilityContext });
  const binding = context.getBinding();
  const proxy = binding.injections[0].object;
  return { load, context, binding, sent, proxy,
    request(method, params = {}) {
      return proxy.onInterceptRequest(JSON.stringify({ type: 'vk-connect', handler: method,
        params: { ...params, request_id: 42 } }), 'route');
    } };
}

test('native cancel reaches VK as User denied with the original request id', async () => {
  const f = fixture({ async startScanForResult() { throw { code: 1000500002, message: 'private' }; } });
  try {
    assert.equal(f.request('VKWebAppOpenCodeReader').timeout, -1);
    await flush();
    assert.equal(f.sent.length, 1);
    assert.deepEqual(f.sent[0].data, { type: 'VKWebAppOpenCodeReaderFailed', data: {
      request_id: 42, error_type: 'client_error', error_data: { error_code: 4, error_reason: 'User denied' }
    } });
  } finally { f.context.close(); }
});

test('missing and invalid native parameters return codes 2 and 5; web auth passes through', async () => {
  const f = fixture();
  try {
    for (const [params, code] of [[{}, 2], [{ level: null }, 5], [{ level: '1' }, 5], [{ level: 2 }, 5]]) {
      f.sent.length = 0;
      f.request('VKWebAppFlashSetLevel', params);
      await flush();
      assert.equal(f.sent.length, 1);
      assert.equal(f.sent[0].data.data.error_data.error_code, code);
    }
    f.sent.length = 0;
    assert.equal(f.request('VKWebAppGetAuthToken', {}).intercept, false);
    await flush();
    assert.equal(f.sent.length, 0);
  } finally { f.context.close(); }
});

test('protocol accepts explicit event names and does not mutate or trust payload request ids', () => {
  const load = createLoader();
  const { VkBridgeProtocol } = load('main/ets/vendors/vk/VkBridgeProtocol');
  const payload = Object.freeze({ result: true, request_id: 'forged' });
  const event = VkBridgeProtocol.success('SpecialReceived', 42, payload);
  assert.equal(event.type, 'SpecialReceived');
  assert.deepEqual(event.data, { result: true, request_id: 42 });
  assert.equal(payload.request_id, 'forged');
  assert.deepEqual(VkBridgeProtocol.success('SpecialReceived', undefined, payload).data, { result: true });
});

test('scanner busy state and late results remain isolated after navigation or close', async () => {
  for (const close of [false, true]) {
    let finish;
    const f = fixture({ startScanForResult: () => new Promise(resolve => { finish = resolve; }) });
    f.request('VKWebAppOpenCodeReader');
    await flush();
    f.request('VKWebAppOpenCodeReader');
    await flush();
    assert.equal(f.sent.length, 1);
    f.sent.length = 0;
    if (close) f.context.close();
    else f.context.beginDocument('https://vk.ru/app1?next');
    finish({ originalValue: 'late', scanType: 11 });
    await flush();
    assert.equal(f.sent.length, 0);
    f.context.close();
  }
});

test('explicit error types preserve schema, data references and supported client reasons', () => {
  const load = createLoader();
  const { VkBridgeError } = load('main/ets/vendors/vk/VkBridgeError');
  const { VkBridgeProtocol } = load('main/ets/vendors/vk/VkBridgeProtocol');
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  const reasons = ['Unknown error', 'Missing required params', 'Connection lost', 'User denied', 'Invalid params',
    'Unsupported platform', 'No device permission', 'Need user permission',
    'This action cannot be performed in the background', 'Requests limit reached', 'Access denied',
    'Uninitialized app', 'Custom error for every handler'];
  for (let code = 1; code <= 13; code++) {
    const error = VkBridgeError.client(code, 'safe');
    assert.ok(error instanceof MiniAppError);
    assert.deepEqual(error.toData(), { error_type: 'client_error', error_data: {
      error_code: code, error_reason: reasons[code - 1], error_description: 'safe'
    } });
  }
  assert.equal(VkBridgeError.client(20).toData().error_data.error_reason, 'No ads');
  const params = [{ key: 'safe', value: 2 }, null];
  const api = VkBridgeError.api({ error_code: 5, error_msg: 'denied', request_params: params, secret: 'private' });
  const event = VkBridgeProtocol.failure('SpecialFailed', 'request', api);
  assert.deepEqual(event, { type: 'SpecialFailed', data: { error_type: 'api_error', error_data: {
    error_code: 5, error_msg: 'denied', request_params: [{ key: 'safe', value: 2 }, null]
  }, request_id: 'request' } });
  assert.equal(api.toData().error_data.request_params, params);
  assert.equal(api.toData().request_id, undefined);
  assert.notEqual(api.toData(), api.toData());
  assert.deepEqual(VkBridgeError.auth({ error: 7, error_reason: 'denied' }).toData(), {
    error_type: 'auth_error', error_data: { error: 7, error_reason: 'denied' }
  });
  const unknown = { error_type: 'client_error', error_data: { error_code: 1, error_reason: 'Unknown error' } };
  assert.deepEqual(VkBridgeError.client().toData(), unknown);
  const cycle = {}; cycle.self = cycle;
  const cause = new Error('original failure');
  const fallback = VkBridgeError.api({ error_code: 1, error_msg: 'x', request_params: [cycle] }, cause);
  assert.equal(fallback.toData().error_data.request_params[0], cycle);
  assert.equal(fallback.originalCause, cause);
  assert.equal(VkBridgeError.auth({ error: 1, error_reason: 'x', error_description: [cycle] })
    .toData().error_data.error_description[0], cycle);
  for (const error of [new Error('secret'), { code: 'USER_CANCELLED', message: 'secret' },
    new MiniAppError('CAPABILITY_BUSY', 'secret'), new MiniAppError('TIMEOUT', 'secret')]) {
    assert.deepEqual(VkBridgeProtocol.failure('XFailed', undefined, error).data, {
      error_type: 'client_error', error_data: { error_code: 1, error_reason: 'Unknown error' }
    });
  }
});

test('event names are resolved from annotations and invalid names reject the whole batch', () => {
  const load = createLoader();
  const { VkEvent } = load('main/ets/vendors/vk/events/VkEvent');
  const { VkEventRegistry } = load('main/ets/vendors/vk/events/VkEventRegistry');
  const context = { id: 'registry', vendorId: 'vk' };
  function handler(options) {
    class Handler { constructor() { this.context = context; } async run() { return {}; } dispose() {} }
    VkEvent(options)(Handler.prototype, 'run', Object.getOwnPropertyDescriptor(Handler.prototype, 'run'));
    return new Handler();
  }
  const registry = new VkEventRegistry(context);
  registry.initHandler([handler({ name: 'Ordinary' }), handler({ name: 'Custom', resultEvent: 'Received', failureEvent: 'Rejected' })]);
  assert.equal(registry.getHandler('Ordinary').resultEvent, 'OrdinaryResult');
  assert.equal(registry.getHandler('Custom').failureEvent, 'Rejected');
  for (const [index, empty] of [undefined, '', '   '].entries()) {
    const name = 'Fallback' + index;
    registry.initHandler([handler({ name, resultEvent: empty, failureEvent: empty })]);
    assert.equal(registry.getHandler(name).resultEvent, name + 'Result');
    assert.equal(registry.getHandler(name).failureEvent, name + 'Failed');
  }
  for (const field of ['resultEvent', 'failureEvent']) {
    for (const invalid of [1, null]) {
      assert.throws(() => registry.initHandler([handler({ name: 'Valid' }), handler({ name: 'Invalid', [field]: invalid })]));
      assert.equal(registry.getHandler('Valid'), undefined);
    }
  }
});

test('serialization failures return one safe error and returned business fields are not control metadata', async () => {
  const f = fixture();
  const { VkEventRegistry } = f.load('main/ets/vendors/vk/events/VkEventRegistry');
  const { VkBridgeProxy } = f.load('main/ets/vendors/vk/VkBridgeProxy');
  const registry = new VkEventRegistry(f.context);
  const proxy = new VkBridgeProxy(f.context, registry);
  const cycle = {}; cycle.self = cycle;
  for (const result of [cycle, { get secret() { throw new Error('private getter'); } }]) {
    const name = 'Method' + registry.getSupportedHandlers().length;
    registry.registerEventHandler(name, { callback: async () => result, timeout: 30000,
      resultEvent: 'Received', failureEvent: 'Rejected' });
    f.sent.length = 0;
    proxy.onInterceptRequest(JSON.stringify({ type: 'vk-connect', handler: name, params: { request_id: 2 } }), 'r');
    await flush();
    assert.equal(f.sent.length, 1);
    assert.equal(f.sent[0].data.type, 'Rejected');
    assert.deepEqual(f.sent[0].data.data.error_data, { error_code: 1, error_reason: 'Unknown error' });
  }
  const { VkBridgeProtocol } = f.load('main/ets/vendors/vk/VkBridgeProtocol');
  const data = { type: 'Other', error_type: 'api_error', outcome: 'failure', data: { value: 1 } };
  assert.deepEqual(VkBridgeProtocol.success('Received', undefined, data), { type: 'Received', data });
  assert.equal(VkBridgeProtocol.success('Received', undefined, data).data.data, data.data);
  f.context.close(); proxy.dispose(); registry.dispose();
});

test('auth without a host callback passes through to VK Web', async () => {
  const f = fixture();
  try {
    assert.equal(f.request('VKWebAppGetAuthToken', { app_id: 1, scope: '' }).intercept, false);
    await flush();
    assert.equal(f.sent.length, 0);
  } finally { f.context.close(); }
});

test('three explicit error types reach the proxy unchanged and failed sends never retry', async () => {
  const f = fixture();
  const { VkEventRegistry } = f.load('main/ets/vendors/vk/events/VkEventRegistry');
  const { VkBridgeProxy } = f.load('main/ets/vendors/vk/VkBridgeProxy');
  const { VkBridgeError } = f.load('main/ets/vendors/vk/VkBridgeError');
  const registry = new VkEventRegistry(f.context);
  const proxy = new VkBridgeProxy(f.context, registry);
  const errors = [VkBridgeError.client(7), VkBridgeError.api({ error_code: 5, error_msg: 'safe', request_params: [] }),
    VkBridgeError.auth({ error: 1, error_reason: 'safe', error_description: ['detail'] })];
  for (let i = 0; i < errors.length; i++) {
    registry.registerEventHandler('E' + i, { callback: async () => { throw errors[i]; }, timeout: 1,
      resultEvent: 'Received', failureEvent: 'Rejected' });
    f.sent.length = 0;
    proxy.onInterceptRequest(JSON.stringify({ type: 'vk-connect', handler: 'E' + i, params: { request_id: i } }), 'r');
    await flush();
    assert.equal(f.sent.length, 1);
    assert.deepEqual(f.sent[0].data, { type: 'Rejected', data: { ...errors[i].toData(), request_id: i } });
  }
  const cycle = {}; cycle.self = cycle;
  const cyclicError = VkBridgeError.api({ error_code: 5, error_msg: 'safe', request_params: [cycle] });
  registry.registerEventHandler('Cyclic', { callback: async () => { throw cyclicError; }, timeout: 1,
    resultEvent: 'Received', failureEvent: 'Rejected' });
  f.sent.length = 0;
  proxy.onInterceptRequest(JSON.stringify({ type: 'vk-connect', handler: 'Cyclic', params: { request_id: 99 } }), 'r');
  await flush();
  assert.equal(f.sent.length, 1);
  assert.deepEqual(f.sent[0].data, { type: 'Rejected', data: {
    error_type: 'client_error', error_data: { error_code: 1, error_reason: 'Unknown error' }, request_id: 99
  } });
  for (const throws of [false, true]) {
    let sends = 0;
    f.context.send = async () => { sends++; if (throws) throw new Error('transport'); return false; };
    proxy.onInterceptRequest(JSON.stringify({ type: 'vk-connect', handler: 'E0', params: {} }), 'r');
    await flush();
    assert.equal(sends, 1);
  }
  f.context.close(); proxy.dispose(); registry.dispose();
});

test('same appId instances retain independent pending reply ownership', async () => {
  const load = createLoader();
  const { VkEventRegistry } = load('main/ets/vendors/vk/events/VkEventRegistry');
  const { VkBridgeProxy } = load('main/ets/vendors/vk/VkBridgeProxy');
  function create(id) {
    const sent = [];
    const context = createTestSession(load, { id, appId: 'same',
      onScript(script) { sent.push(script); } });
    let finish;
    const registry = new VkEventRegistry(context);
    registry.registerEventHandler('Wait', { callback: () => new Promise(resolve => { finish = resolve; }),
      timeout: 0, resultEvent: 'Received', failureEvent: 'Rejected' });
    const proxy = new VkBridgeProxy(context, registry);
    proxy.onInterceptRequest('{"type":"vk-connect","handler":"Wait","params":{"request_id":1}}', id);
    return { context, sent, registry, proxy, finish };
  }
  const first = create('first'), second = create('second');
  first.context.close(); first.proxy.dispose(); first.registry.dispose();
  first.finish({ value: 'old' }); second.finish({ value: 'new' });
  await flush();
  assert.equal(first.sent.length, 0);
  assert.equal(second.sent.length, 1);
  assert.ok(second.sent[0].includes('second'));
  assert.ok(second.sent[0].includes('new'));
  second.context.close(); second.proxy.dispose(); second.registry.dispose();
});


test('VK media owns cancellation conversion before protocol serialization', async () => {
  const load = createLoader();
  const { VkMediaHandler } = load('main/ets/vendors/vk/handlers/VkMediaHandler');
  const { VkBridgeError } = load('main/ets/vendors/vk/VkBridgeError');
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  const cause = new MiniAppError('USER_CANCELLED', 'private');
  const { CodeReaderTools } = load('main/ets/capabilities/media/CodeReaderTools');
  CodeReaderTools.prototype.read = async function () { throw cause; };
  const handler = new VkMediaHandler({ getDocumentId: () => 1, addCleanup() {} });
  await assert.rejects(handler.openCodeReader({}), error => {
    assert.ok(error instanceof VkBridgeError);
    assert.equal(error.toData().error_data.error_code, 4);
    assert.equal(error.originalCause, cause);
    return true;
  });
});

test('protocol translates SDK missing and invalid parameter errors', () => {
  const load = createLoader();
  const { VkBridgeProtocol } = load('main/ets/vendors/vk/VkBridgeProtocol');
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  assert.equal(VkBridgeProtocol.failure('Failed', 1, new MiniAppError('INVALID_ARGUMENT', 'private'))
    .data.error_data.error_code, 5);
  assert.equal(VkBridgeProtocol.failure('Failed', 1, new MiniAppError('MISSING_REQUIRED_PARAMS', 'private'))
    .data.error_data.error_code, 2);
  for (const code of ['USER_CANCELLED', 'NOT_SUPPORTED', 'PERMISSION_DENIED']) {
    const reply = VkBridgeProtocol.failure('Failed', 1, new MiniAppError(code, 'private'));
    assert.equal(reply.data.error_data.error_code, 1);
    assert.ok(!JSON.stringify(reply).includes('private'));
  }
});


test('native errors are classified by each VK handler and preserve their cause', async () => {
  const load = createLoader();
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  const { VkBridgeError } = load('main/ets/vendors/vk/VkBridgeError');
  const { VkMediaHandler } = load('main/ets/vendors/vk/handlers/VkMediaHandler');
  const { VkFlashHandler } = load('main/ets/vendors/vk/handlers/VkFlashHandler');
  const { VkHapticHandler } = load('main/ets/vendors/vk/handlers/VkHapticHandler');
  const { VkSwipeSettingsHandler } = load('main/ets/vendors/vk/handlers/VkSwipeSettingsHandler');
  const context = { getDocumentId: () => 1, addCleanup() {} };
  const cases = [
    [cause => {
      const { CodeReaderTools } = load('main/ets/capabilities/media/CodeReaderTools');
      CodeReaderTools.prototype.read = async function () { throw cause; };
      return new VkMediaHandler(context).openCodeReader({});
    }, { USER_CANCELLED: 4, NOT_SUPPORTED: 6, CAPABILITY_BUSY: 1, PERMISSION_DENIED: 1 }],
    [cause => new VkFlashHandler(context, () => ({ async setEnabled() { throw cause; }, dispose() {} }))
      .setFlashLevel({ level: 1 }), { USER_CANCELLED: 4, PERMISSION_DENIED: 7, NOT_SUPPORTED: 6, SESSION_CLOSED: 1 }],
    [cause => new VkHapticHandler(context, async () => { throw cause; })
      .selectionChanged({}), { PERMISSION_DENIED: 7, NOT_SUPPORTED: 6, USER_CANCELLED: 1 }],
    [cause => new VkSwipeSettingsHandler({ setSwipeBackEnabled() { throw cause; } })
      .setSwipeSettings({ history: true }), { NOT_SUPPORTED: 6, SESSION_CLOSED: 1 }]
  ];
  for (const [invoke, mappings] of cases) {
    for (const [code, expected] of Object.entries({ ...mappings, SYSTEM_ERROR: 1 })) {
      const cause = new MiniAppError(code, 'private-native-detail');
      await assert.rejects(invoke(cause), error => {
        assert.ok(error instanceof VkBridgeError);
        assert.equal(error.toData().error_data.error_code, expected);
        assert.equal(error.originalCause, cause);
        assert.ok(!JSON.stringify(error.toData()).includes('private-native-detail'));
        return true;
      });
    }
  }
});

test('host callbacks cannot bypass adapter sanitization with a VK error', async () => {
  const load = createLoader();
  const { VkAdapter } = load('main/ets/vendors/vk/VkAdapter');
  const { VkBridgeError } = load('main/ets/vendors/vk/VkBridgeError');
  const cause = VkBridgeError.auth({ error: 5, error_reason: 'private-host-detail' });
  const adapter = new VkAdapter({ async onAuthTokenRequest() { throw cause; } });
  await assert.rejects(adapter.requestAuthToken({ appId: 1, scope: '' }), error => {
    assert.ok(error instanceof VkBridgeError);
    assert.equal(error.toData().error_type, 'client_error');
    assert.equal(error.toData().error_data.error_code, 1);
    assert.equal(error.originalCause, cause);
    assert.ok(!JSON.stringify(error.toData()).includes('private-host-detail'));
    return true;
  });
});


test('host parameter errors are sanitized before parameter error translation', async () => {
  const load = createLoader();
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  const { VkAdapter } = load('main/ets/vendors/vk/VkAdapter');
  const { VkBridgeProtocol } = load('main/ets/vendors/vk/VkBridgeProtocol');
  for (const code of ['INVALID_ARGUMENT', 'MISSING_REQUIRED_PARAMS']) {
    const adapter = new VkAdapter({ async onAuthTokenRequest() {
      throw new MiniAppError(code, 'private-host-detail');
    } });
    await assert.rejects(adapter.requestAuthToken({ appId: 1, scope: '' }), error => {
      const reply = VkBridgeProtocol.failure('Failed', 1, error);
      assert.equal(reply.data.error_data.error_code, 1);
      assert.ok(!JSON.stringify(reply).includes('private-host-detail'));
      return true;
    });
  }
});

test('VK media directly creates scanner and releases it on page cleanup', async () => {
  const load = createLoader();
  const { CodeReaderTools } = load('main/ets/capabilities/media/CodeReaderTools');
  const { VkMediaHandler } = load('main/ets/vendors/vk/handlers/VkMediaHandler');
  let resolve; let releases = 0; let documentId = 1; const cleanups = [];
  CodeReaderTools.prototype.read = function () { return new Promise(r => { resolve = r; }); };
  CodeReaderTools.prototype.dispose = function () { releases++; };
  const handler = new VkMediaHandler({ getDocumentId: () => documentId, addCleanup(fn) { cleanups.push(fn); } });
  const first = handler.openCodeReader({}); resolve('raw-code');
  assert.deepEqual(await first, { code_data: 'raw-code' });
  const stale = handler.openCodeReader({}); documentId++;
  cleanups.splice(0).forEach(fn => fn()); resolve('old');
  await assert.rejects(stale);
  assert.equal(releases, 1);
  const next = handler.openCodeReader({}); resolve('next');
  assert.deepEqual(await next, { code_data: 'next' });
  handler.dispose(); handler.dispose();
  assert.equal(releases, 2);
  await assert.rejects(handler.openCodeReader({}));
});
