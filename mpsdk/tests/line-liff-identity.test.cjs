const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');

test('one LINE adapter resolves each session independently and never substitutes the entry alias', () => {
  const { LineAdapter } = createLoader()('main/ets/vendors/line/LineAdapter');
  const adapter = new LineAdapter();
  const states = new Map();
  const session = name => ({ vendorId: 'line', appId: name,
    getAdapter: () => adapter, getBinding: () => ({ getAppState: () => states.get(name) }) });
  const first = session('first-alias'), second = session('second-alias');
  assert.equal(adapter.getLiffId(first), undefined);
  states.set(first.appId, { liffId: 'first-id', featureToken: 'first-feature' });
  states.set(second.appId, { liffId: 'second-id', featureToken: 'second-feature' });
  assert.equal(first.getAdapter().getLiffId(first), 'first-id');
  assert.equal(second.getAdapter().getLiffId(second), 'second-id');
  states.delete(first.appId);
  assert.equal(adapter.getLiffId(first), undefined);
  assert.equal(adapter.getLiffId(second), 'second-id');
  assert.throws(() => adapter.getLiffId({ ...second, vendorId: 'vk' }), { code: 'INVALID_ARGUMENT' });
});
