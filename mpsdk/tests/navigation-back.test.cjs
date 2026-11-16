const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('explicit back only navigates attached history and ignores stale detach', () => {
  const load = createLoader();
  const { MiniAppNavigationController } = load('main/ets/web/MiniAppNavigationController');
  const navigation = new MiniAppNavigationController();
  let count = 0;
  let hasHistory = false;
  const endpoint = { controller: {
    accessBackward: () => hasHistory,
    backward: () => { count++; }
  } };
  assert.equal(navigation.goBack(), false);
  navigation.attach(endpoint);
  assert.equal(navigation.goBack(), false);
  hasHistory = true;
  assert.equal(navigation.goBack(), true);
  navigation.detach({});
  assert.equal(navigation.goBack(), true);
  navigation.detach(endpoint);
  assert.equal(navigation.goBack(), false);
  assert.equal(count, 2);
});

test('platform back failures are errors rather than a signal to close the page', () => {
  const load = createLoader();
  const { MiniAppNavigationController } = load('main/ets/web/MiniAppNavigationController');
  const navigation = new MiniAppNavigationController();
  for (const failReading of [true, false]) {
    const cause = new Error('platform failure');
    navigation.attach({ controller: {
      accessBackward: () => { if (failReading) throw cause; return true; },
      backward: () => { throw cause; }
    } });
    assert.throws(() => navigation.goBack(), error =>
      error.code === 'WEB_CONTAINER_FAILED' && error.originalCause === cause);
  }
});
