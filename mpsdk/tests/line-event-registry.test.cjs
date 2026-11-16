const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function fixture() {
  const load = createLoader();
  const { LineEventRegistry } = load('main/ets/vendors/line/LineEventRegistry');
  const context = { id: 'session', appId: 'same-app' };
  const registry = new LineEventRegistry(context);
  return { load, context, registry };
}

class TestHandler {
  constructor(context, type) {
    this.context = context;
    this.type = type;
    this.disposals = 0;
  }
  async handle(params) { return { type: this.type, value: params.value }; }
  dispose() { this.disposals++; }
}

test('registration enables handlers without an availability flag and preserves the receiver', async () => {
  const { context, registry } = fixture();
  const active = new TestHandler(context, 'active'), second = new TestHandler(context, 'second');
  registry.initHandler([active, second]);
  assert.deepEqual(registry.getFeatures(), ['active', 'second']);
  assert.equal(registry.getHandler('active'), active);
  assert.deepEqual(await registry.getHandler('active').handle({ value: 'raw' }), { type: 'active', value: 'raw' });
  assert.equal(registry.getHandler('second'), second);
  assert.equal(registry.isKnownMethod('openWindow'), true);
  assert.equal(registry.getHandler('openWindow'), undefined);
  registry.dispose();
  assert.equal(active.disposals, 1);
  assert.equal(second.disposals, 1);
});

test('same handler repeated within or across batches is owned and released once', () => {
  const { context, registry } = fixture();
  const handler = new TestHandler(context, 'once');
  registry.initHandler([handler, handler]);
  registry.initHandler([handler]);
  assert.deepEqual(registry.getFeatures(), ['once']);
  registry.dispose(); registry.dispose();
  assert.equal(handler.disposals, 1);
});

test('conflicting names reject the whole batch and leave rejected instances with the caller', () => {
  for (const existing of [false, true]) {
    const { context, registry } = fixture();
    const original = new TestHandler(context, 'duplicate');
    if (existing) registry.initHandler([original]);
    const first = new TestHandler(context, 'first'), duplicate = new TestHandler(context, 'duplicate');
    const pending = existing ? [first, duplicate] : [first, original, duplicate];
    assert.throws(() => registry.initHandler(pending), { code: 'CAPABILITY_ALREADY_REGISTERED_OR_INVALID' });
    assert.deepEqual(registry.getFeatures(), existing ? ['duplicate'] : []);
    registry.dispose();
    assert.equal(first.disposals, 0);
    assert.equal(duplicate.disposals, 0);
    assert.equal(original.disposals, existing ? 1 : 0);
    pending.forEach(handler => handler.dispose()); // caller still owns rejected batch
  }
});

test('foreign sessions and invalid metadata cannot partially register handlers', () => {
  for (const invalid of ['context', 'type']) {
    const { context, registry } = fixture();
    const first = new TestHandler(context, 'first'), bad = new TestHandler(context, 'bad');
    if (invalid === 'context') bad.context = { id: 'other-session', appId: context.appId };
    if (invalid === 'type') bad.type = '';
    assert.throws(() => registry.initHandler([first, bad]), {
      code: invalid === 'context' ? 'CAPABILITY_ALREADY_REGISTERED_OR_INVALID' : 'INVALID_ARGUMENT'
    });
    assert.deepEqual(registry.getFeatures(), []);
    registry.dispose();
    assert.equal(first.disposals, 0);
    assert.equal(bad.disposals, 0);
  }
});

test('dispose disables dispatch before cleanup, tolerates failure and ignores reentrant disposal', () => {
  const { context, registry, load } = fixture();
  const first = new TestHandler(context, 'first'), second = new TestHandler(context, 'second');
  const logs = [];
  load('main/ets/logging/SdkLogger').SdkLogger.install({ write(_level, event, details) { logs.push({ event, details }); } });
  first.dispose = () => {
    first.disposals++;
    assert.equal(registry.isActive(), false);
    assert.deepEqual(registry.getFeatures(), []);
    assert.equal(registry.getHandler('second'), undefined);
    registry.dispose();
    throw new Error('private token');
  };
  registry.initHandler([first, second]);
  registry.dispose(); registry.dispose();
  assert.equal(first.disposals, 1);
  assert.equal(second.disposals, 1);
  assert.ok(logs.some(log => log.event === 'LineEventRegistry.disposeFailed'));
  assert.equal(JSON.stringify(logs).includes('private token'), false);
});

test('closed registry rejects new ownership and clears custom known methods', () => {
  const { context, registry } = fixture();
  const handler = new TestHandler(context, 'custom');
  registry.initHandler([handler]); registry.dispose();
  assert.equal(registry.isKnownMethod('custom'), false);
  const late = new TestHandler(context, 'late');
  assert.throws(() => registry.initHandler([late]), { code: 'SESSION_CLOSED' });
  assert.equal(late.disposals, 0);
});

test('Binding releases a rejected handler batch even if one cleanup throws', () => {
  const { load } = fixture();
  const { LineEventRegistry } = load('main/ets/vendors/line/LineEventRegistry');
  const { LineBinding } = load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const adapter = new LineAdapter({ mode: 'client' });
  const disposed = [];
  let rejectedRegistry;
  LineEventRegistry.prototype.initHandler = function (handlers) {
    rejectedRegistry = this;
    handlers.forEach((handler, index) => {
      const original = handler.dispose.bind(handler);
      handler.dispose = () => {
        disposed.push(handler.type);
        original();
        if (index === 0) throw new Error('cleanup failed');
      };
    });
    throw new Error('registration failed');
  };
  const session = { id: 'failed-binding', appId: 'app', info: {}, uiAbilityContext: {},
    getAdapter: () => adapter, getDocumentId: () => 1 };
  assert.throws(() => new LineBinding(session), { code: 'VENDOR_BINDING_FAILED' });
  assert.deepEqual(disposed, ['closeWindow', 'scanCode', 'openWindow']);
  assert.equal(rejectedRegistry.isActive(), false);
});

test('Binding delegates successful handler cleanup to the registry exactly once', () => {
  const { load } = fixture();
  const { LineEventRegistry } = load('main/ets/vendors/line/LineEventRegistry');
  const { LineBinding } = load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const adapter = new LineAdapter({ mode: 'client' });
  const disposed = [];
  const init = LineEventRegistry.prototype.initHandler;
  LineEventRegistry.prototype.initHandler = function (handlers) {
    handlers.forEach((handler, index) => {
      const original = handler.dispose.bind(handler);
      handler.dispose = () => {
        assert.equal(this.isActive(), false);
        assert.deepEqual(this.getFeatures(), []);
        disposed.push(handler.type);
        original();
        if (index === 0) throw new Error('cleanup failed');
      };
    });
    init.call(this, handlers);
  };
  const session = { id: 'binding', appId: 'app', info: {}, uiAbilityContext: {},
    getAdapter: () => adapter, getDocumentId: () => 1 };
  const binding = new LineBinding(session);
  binding.dispose(); binding.dispose();
  assert.deepEqual(disposed, ['closeWindow', 'scanCode', 'openWindow']);
  assert.deepEqual(binding.injections, []);
});
