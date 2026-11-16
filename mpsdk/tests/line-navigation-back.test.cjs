const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');

function fixture({ child = false, blocked = false, enabled = true, history = true, platformFailure = false } = {}) {
  const load = createLoader();
  const { LineNavigationController } = load('main/ets/vendors/line/LineNavigationController');
  const { LineBinding } = load('main/ets/vendors/line/LineVendor');
  const binding = Object.create(LineBinding.prototype);
  const calls = [];
  binding.requestSubWindowClose = () => { calls.push('child'); return child; };
  const session = {
    getBinding: () => binding,
    handleBackPress: () => { calls.push('policy'); return blocked; },
    isBackPressHandlingEnabled: () => enabled
  };
  const navigation = new LineNavigationController();
  const endpoint = { session, controller: {
    accessBackward: () => { calls.push('history'); if (platformFailure) throw new Error('platform'); return history; },
    backward: () => calls.push('backward')
  } };
  navigation.attach(endpoint);
  return { navigation, endpoint, calls };
}

test('LINE system back returns through WebView history after OAuth instead of closing its container', () => {
  const f = fixture();
  assert.equal(f.navigation.handleBackPress(), true);
  assert.deepEqual(f.calls, ['child', 'policy', 'history', 'backward']);
});

test('LINE system back preserves child and back-control priority before inspecting history', () => {
  const child = fixture({ child: true });
  assert.equal(child.navigation.handleBackPress(), true);
  assert.deepEqual(child.calls, ['child']);
  const blocked = fixture({ blocked: true });
  assert.equal(blocked.navigation.handleBackPress(), true);
  assert.deepEqual(blocked.calls, ['child', 'policy']);
});

test('LINE returns to the host only when history is absent, and never reads history without host opt-in', () => {
  const empty = fixture({ history: false });
  assert.equal(empty.navigation.handleBackPress(), false);
  assert.deepEqual(empty.calls, ['child', 'policy', 'history']);
  const disabled = fixture({ enabled: false });
  assert.equal(disabled.navigation.handleBackPress(), false);
  assert.deepEqual(disabled.calls, ['child', 'policy']);
  disabled.navigation.detach(disabled.endpoint);
  assert.equal(disabled.navigation.handleBackPress(), false);
});

test('LINE history failures remain errors and cannot signal the host to close the container', () => {
  const f = fixture({ platformFailure: true });
  assert.throws(() => f.navigation.handleBackPress(), error => error.code === 'WEB_CONTAINER_FAILED');
});
