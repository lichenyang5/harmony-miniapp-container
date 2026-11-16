const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('SDK initializes one application listener and isolates host lifetimes', () => {
  const load = createLoader();
  const { MiniAppSDK } = load('main/ets/core/MiniAppSDK');
  let callback, registrations = 0;
  const application = { on(event, listener) {
    assert.equal(event, 'abilityLifecycle');
    registrations++;
    callback = listener;
    return 0;
  } };
  assert.equal(typeof MiniAppSDK.initialize, 'function');
  MiniAppSDK.initialize(application);
  MiniAppSDK.initialize(application);
  assert.equal(registrations, 1);
  const { assertHostForeground } = load('main/ets/core/HostLifecycleMonitor');
  const a = { context: {} }, b = { context: {} };
  const rejects = (ability, code) => assert.throws(() => assertHostForeground(ability.context), { code });
  rejects(a, 'HOST_LIFECYCLE_NOT_INITIALIZED');
  callback.onAbilityCreate(a);
  callback.onAbilityCreate(b);
  rejects(a, 'APP_IN_BACKGROUND');
  callback.onAbilityForeground(a);
  assertHostForeground(a.context);
  rejects(b, 'APP_IN_BACKGROUND');
  callback.onAbilityCreate(a); // duplicate must not reset foreground
  MiniAppSDK.initialize(application);
  assertHostForeground(a.context);
  callback.onAbilityWillBackground(a);
  rejects(a, 'APP_IN_BACKGROUND');
  callback.onAbilityForeground(b);
  callback.onAbilityWillDestroy(a);
  callback.onAbilityDestroy(a);
  callback.onAbilityForeground(a);
  callback.onAbilityBackground(a);
  rejects(a, 'HOST_LIFECYCLE_NOT_INITIALIZED');
  assertHostForeground(b.context);
  const c = { context: {} };
  callback.onAbilityCreate(c);
  callback.onAbilityForeground(c);
  assertHostForeground(c.context);
  assert.equal(registrations, 1);
});

test('failed application subscription preserves cause and permits retry', () => {
  const load = createLoader();
  const { MiniAppSDK } = load('main/ets/core/MiniAppSDK');
  const cause = new Error('registration failed');
  let calls = 0;
  const application = { on() { if (++calls === 1) throw cause; return 0; } };
  assert.equal(typeof MiniAppSDK.initialize, 'function');
  assert.throws(() => MiniAppSDK.initialize(application), error =>
    error.code === 'HOST_LIFECYCLE_INIT_FAILED' && error.originalCause === cause);
  MiniAppSDK.initialize(application);
  MiniAppSDK.initialize(application);
  assert.equal(calls, 2);
});

test('host observers receive an atomic snapshot and scoped distinct changes', () => {
  const load = createLoader();
  const { HostLifecycleMonitor } = load('main/ets/core/HostLifecycleMonitor');
  const a = { context: {} }, b = { context: {} };
  const events = [], other = [];
  const unsubscribe = HostLifecycleMonitor.observe(a.context, {
    onForegroundChanged: value => events.push(value), onDestroyed: () => events.push('destroyed')
  });
  let callback;
  HostLifecycleMonitor.initialize(listener => { callback = listener; return 0; });
  HostLifecycleMonitor.observe(b.context, {
    onForegroundChanged: value => other.push(value), onDestroyed() {}
  });
  assert.deepEqual(events, [false]);
  callback.onAbilityCreate(a);
  callback.onAbilityCreate(b);
  callback.onAbilityForeground(a);
  callback.onAbilityForeground(a);
  callback.onAbilityWillBackground(a);
  callback.onAbilityBackground(a);
  assert.deepEqual(events, [false, true, false]);
  assert.deepEqual(other, [false]);
  callback.onAbilityForeground(a);
  const snapshot = [];
  HostLifecycleMonitor.observe(a.context, {
    onForegroundChanged: value => snapshot.push(value), onDestroyed() {}
  });
  assert.deepEqual(snapshot, [true]);
  unsubscribe();
  unsubscribe();
  callback.onAbilityBackground(a);
  assert.deepEqual(events, [false, true, false, true]);
  assert.deepEqual(snapshot, [true, false]);
});

test('destroy clears observers, isolates exceptions and ignores late host events', () => {
  const load = createLoader();
  const { HostLifecycleMonitor } = load('main/ets/core/HostLifecycleMonitor');
  let callback;
  HostLifecycleMonitor.initialize(listener => { callback = listener; return 0; });
  const ability = { context: {} };
  callback.onAbilityCreate(ability);
  HostLifecycleMonitor.observe(ability.context, {
    onForegroundChanged() { throw new Error('observer'); },
    onDestroyed() { throw new Error('observer'); }
  });
  const events = [];
  HostLifecycleMonitor.observe(ability.context, {
    onForegroundChanged: value => events.push(value), onDestroyed: () => events.push('destroyed')
  });
  callback.onAbilityForeground(ability);
  callback.onAbilityWillDestroy(ability);
  callback.onAbilityDestroy(ability);
  callback.onAbilityCreate(ability);
  callback.onAbilityForeground(ability);
  assert.deepEqual(events, [false, true, 'destroyed']);
  const late = [];
  HostLifecycleMonitor.observe(ability.context, {
    onForegroundChanged: value => late.push(value), onDestroyed: () => late.push('destroyed')
  });
  assert.deepEqual(late, ['destroyed']);
});

test('reentrant destruction during a snapshot cannot retain the new observer', () => {
  const load = createLoader();
  const { HostLifecycleMonitor } = load('main/ets/core/HostLifecycleMonitor');
  let callback;
  HostLifecycleMonitor.initialize(listener => { callback = listener; return 0; });
  const ability = { context: {} }, events = [];
  callback.onAbilityCreate(ability);
  callback.onAbilityForeground(ability);
  const unsubscribe = HostLifecycleMonitor.observe(ability.context, {
    onForegroundChanged(value) { events.push(value); callback.onAbilityDestroy(ability); },
    onDestroyed() { events.push('destroyed'); }
  });
  unsubscribe();
  callback.onAbilityForeground(ability);
  assert.deepEqual(events, [true, 'destroyed']);
});
