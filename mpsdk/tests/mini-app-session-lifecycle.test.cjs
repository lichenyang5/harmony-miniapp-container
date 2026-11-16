const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { applicationLifecycle } = require('./application-lifecycle.cjs');

function fixture() {
  const load = createLoader();
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { MiniAppLifecycleController } = load('main/ets/core/lifecycle/MiniAppLifecycleController');
  const host = applicationLifecycle(load);
  const make = (context, initiallyActive = true, onOpenMiniApp) => {
    const controller = new MiniAppLifecycleController(initiallyActive);
    const changes = [];
    const session = new MiniAppSession('instance', {
      info: { vendor: 'test', appId: 'same-app', url: 'https://example.com' },
      vendor: { vendorId: 'test', createBinding: () => ({ injections: [], scripts: [],
        onDocumentChanged() {}, onLifecycleChanged: change => changes.push(change.current), dispose() {} }) },
      adapter: {}, swipeBackController: { dispose() {} }, lifecycleController: controller, onOpenMiniApp
    }, context);
    let pauses = 0;
    session.attach({ evaluate: async () => '', pauseAllMedia() { pauses++; } });
    return { controller, session, changes, pauses: () => pauses };
  };
  return { load, host, make };
}

test('selection and Ability foreground are independent, same-app instances are isolated and host destruction is terminal', () => {
  const f = fixture(); const a = { context: {} }, b = { context: {} };
  f.host.onAbilityCreate(a); f.host.onAbilityForeground(a); f.host.onAbilityCreate(b);
  const first = f.make(a.context), hidden = f.make(a.context, false), other = f.make(b.context);
  assert.equal(first.controller.getState(), 'FOREGROUND');
  assert.deepEqual(hidden.changes, ['BACKGROUND']);
  assert.equal(other.controller.getState(), 'BACKGROUND');
  first.controller.deactivate(); hidden.controller.activate();
  assert.equal(first.controller.getState(), 'BACKGROUND');
  assert.equal(hidden.controller.getState(), 'FOREGROUND');
  const document = hidden.session.getDocumentId();
  f.host.onAbilityBackground(a); hidden.controller.activate();
  assert.equal(hidden.controller.getState(), 'BACKGROUND');
  f.host.onAbilityForeground(a);
  assert.equal(first.controller.getState(), 'BACKGROUND');
  assert.equal(hidden.controller.getState(), 'FOREGROUND');
  assert.equal(hidden.session.getDocumentId(), document);
  f.host.onAbilityDestroy(a); hidden.controller.activate();
  assert.equal(first.controller.getState(), 'DESTROYED');
  assert.equal(hidden.controller.getState(), 'DESTROYED');
  assert.equal(other.controller.getState(), 'BACKGROUND');
  f.host.onAbilityForeground(b); assert.equal(other.controller.getState(), 'FOREGROUND');
  other.session.close();
});

test('an accepted transfer survives deactivation, while new background requests are rejected', async () => {
  const f = fixture(); const ability = { context: {} };
  f.host.onAbilityCreate(ability); f.host.onAbilityForeground(ability);
  let finish;
  const source = f.make(ability.context, true, () => new Promise(resolve => { finish = resolve; }));
  const target = { vendor: 'test', appId: 'target', url: 'https://example.com/target' };
  const pending = source.session.requestOpenMiniApp(target);
  source.controller.deactivate();
  await assert.rejects(source.session.requestOpenMiniApp(target), { code: 'NOT_SUPPORTED' });
  finish(); await pending;
  source.session.close();
});

test('duplicate lifecycle binding releases the rejected session resource without affecting the first session', () => {
  const f = fixture(); const first = f.make({}); let released = 0;
  const { MiniAppSession } = f.load('main/ets/core/Runtime');
  assert.throws(() => new MiniAppSession('duplicate', {
    info: first.session.info, vendor: first.session.descriptor.vendor, adapter: {},
    lifecycleController: first.controller, swipeBackController: { dispose() { released++; } }
  }, {}), { code: 'SESSION_ALREADY_ATTACHED_OR_CLOSED' });
  assert.equal(released, 1);
  assert.equal(first.controller.getState(), 'BACKGROUND');
  assert.ok(first.session.getBinding()); first.session.close();
});
