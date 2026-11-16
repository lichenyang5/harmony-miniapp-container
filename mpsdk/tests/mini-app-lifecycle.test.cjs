const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function fixture(initiallyActive = true) {
  const load = createLoader();
  const { MiniAppLifecycleController, bindMiniAppLifecycle } =
    load('main/ets/core/lifecycle/MiniAppLifecycleController');
  const controller = new MiniAppLifecycleController(initiallyActive);
  return { controller, bind: () => bindMiniAppLifecycle(controller), MiniAppLifecycleController, bindMiniAppLifecycle };
}

test('premount intent stays CREATED and initially inactive attaches directly in BACKGROUND', () => {
  const f = fixture(false);
  const changes = [];
  f.controller.observe(change => changes.push([change.previous, change.current]));
  f.controller.activate(); f.controller.deactivate();
  assert.equal(f.controller.getState(), 'CREATED');
  assert.equal(f.controller.isForeground(), false);
  const lifecycle = f.bind();
  lifecycle.setHostForeground(true);
  assert.equal(lifecycle.getState(), 'CREATED');
  lifecycle.setAttached();
  assert.deepEqual(changes, [['CREATED', 'BACKGROUND']]);
  f.controller.activate(); f.controller.activate(); lifecycle.setAttached();
  assert.equal(f.controller.isForeground(), true);
  assert.deepEqual(changes, [['CREATED', 'BACKGROUND'], ['BACKGROUND', 'FOREGROUND']]);
});

test('unknown and background hosts prevent foreground while independent instances remain isolated', () => {
  const a = fixture(); const b = fixture();
  const runtimeA = a.bind(); const runtimeB = b.bind();
  runtimeA.setAttached(); runtimeB.setHostForeground(true); runtimeB.setAttached();
  assert.equal(runtimeA.getState(), 'BACKGROUND');
  assert.equal(runtimeB.getState(), 'FOREGROUND');
  a.controller.activate();
  assert.equal(runtimeA.isForeground(), false);
  runtimeA.setHostForeground(true);
  assert.equal(runtimeA.isForeground(), true);
  runtimeA.setHostForeground(false); a.controller.deactivate(); a.controller.activate();
  assert.equal(runtimeA.isForeground(), false);
  assert.equal(runtimeB.isForeground(), true);
  runtimeA.destroy(); assert.equal(runtimeB.isForeground(), true);
});

test('a second claim fails without changing the first runtime and destroyed controllers cannot be reused', () => {
  const f = fixture(); const runtime = f.bind();
  assert.throws(f.bind, error => error.code === 'SESSION_ALREADY_ATTACHED_OR_CLOSED');
  runtime.setHostForeground(true); runtime.setAttached();
  assert.equal(f.controller.getState(), 'FOREGROUND');
  runtime.destroy();
  assert.throws(f.bind, error => error.code === 'SESSION_ALREADY_ATTACHED_OR_CLOSED');
  assert.equal(f.controller.getState(), 'DESTROYED');
  assert.equal(typeof f.controller.destroy, 'undefined');
  assert.equal(typeof f.controller.setHostForeground, 'undefined');
  assert.equal(typeof f.controller.bind, 'undefined');
});

test('notifications commit state first, isolate failures and serialize reentrant inputs', () => {
  const f = fixture(); const runtime = f.bind(); const seen = [];
  runtime.setHostForeground(true);
  f.controller.observe(change => {
    seen.push(['first', change.current, f.controller.getState()]);
    if (change.current === 'FOREGROUND') {
      f.controller.deactivate(); f.controller.activate(); runtime.destroy();
    }
    throw new Error('observer failure');
  });
  runtime.observe(change => seen.push(['second', change.current, runtime.getState()]));
  runtime.setAttached();
  assert.deepEqual(seen, [
    ['first', 'FOREGROUND', 'FOREGROUND'], ['second', 'FOREGROUND', 'FOREGROUND'],
    ['first', 'BACKGROUND', 'BACKGROUND'], ['second', 'BACKGROUND', 'BACKGROUND'],
    ['first', 'FOREGROUND', 'FOREGROUND'], ['second', 'FOREGROUND', 'FOREGROUND'],
    ['first', 'DESTROYED', 'DESTROYED'], ['second', 'DESTROYED', 'DESTROYED']
  ]);
  const count = seen.length;
  f.controller.activate(); f.controller.deactivate(); runtime.setAttached();
  runtime.setHostForeground(true); runtime.destroy();
  f.controller.observe(() => assert.fail('terminal observation fired'))();
  assert.equal(seen.length, count);
  assert.equal(f.controller.isForeground(), false);
});

test('unsubscribe is idempotent and each registration remains independent', () => {
  const f = fixture(); const runtime = f.bind(); const seen = [];
  const listener = change => seen.push(change.current);
  const stop = f.controller.observe(listener);
  runtime.observe(listener);
  stop(); stop();
  runtime.setAttached();
  assert.deepEqual(seen, ['BACKGROUND']);
  runtime.destroy();
  assert.deepEqual(seen, ['BACKGROUND', 'DESTROYED']);
});

test('destroying before attachment sends only DESTROYED and ignores late host inputs', () => {
  const f = fixture(); const runtime = f.bind(); const seen = [];
  f.controller.observe(change => seen.push([change.previous, change.current]));
  assert.deepEqual(seen, []);
  runtime.destroy();
  runtime.setHostForeground(true); runtime.setAttached(); f.controller.activate();
  assert.deepEqual(seen, [['CREATED', 'DESTROYED']]);
  assert.equal(runtime.getState(), 'DESTROYED');
});

test('unsubscribing another observer during notification prevents its callback', () => {
  const f = fixture(); const runtime = f.bind(); const seen = [];
  let stop;
  f.controller.observe(() => { seen.push('first'); stop(); });
  stop = f.controller.observe(() => seen.push('removed'));
  runtime.setAttached();
  assert.deepEqual(seen, ['first']);
});

test('reentrant destroy keeps notification order and discards inputs queued after destroy', () => {
  const f = fixture(); const runtime = f.bind(); const seen = [];
  runtime.setHostForeground(true);
  f.controller.observe(change => {
    if (change.current === 'FOREGROUND') {
      runtime.destroy();
      f.controller.deactivate(); runtime.setHostForeground(false); f.controller.activate();
    }
  });
  runtime.observe(change => seen.push([change.current, runtime.getState()]));
  runtime.setAttached();
  assert.deepEqual(seen, [['FOREGROUND', 'FOREGROUND'], ['DESTROYED', 'DESTROYED']]);
  assert.equal(runtime.isForeground(), false);
});
