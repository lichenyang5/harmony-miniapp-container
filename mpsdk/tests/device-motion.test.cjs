const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('device motion start uses the default rate and delivers alpha beta gamma', async () => {
  const load = createLoader();
  const { VkDeviceMotionHandler } = load('main/ets/vendors/vk/handlers/VkDeviceMotionHandler');
  const { VkEventRegistry } = load('main/ets/vendors/vk/events/VkEventRegistry');
  const rates = [];
  const received = [];
  let listener;
  const context = {
    id: 'device-motion', vendorId: 'vk', getDocumentId: () => 1, addCleanup() {},
    async send(script) {
      new Function('window', script)({ atomicBridge: { postEvent(data) { received.push(data); } } });
      return true;
    }
  };
  const source = {
    start(rate, next) { rates.push(rate); listener = next; },
    stop() {}
  };
  const handler = new VkDeviceMotionHandler(context, source);
  const registry = new VkEventRegistry(context);
  registry.initHandler([handler]);
  assert.ok(registry.getHandler('VKWebAppDeviceMotionStart'));
  assert.ok(registry.getHandler('VKWebAppDeviceMotionStop'));

  assert.deepEqual(await handler.start({}), { result: true });
  assert.deepEqual(rates, [1000]);
  listener({ alpha: 0.1, beta: -0.2, gamma: 0.3 });
  await Promise.resolve();

  assert.deepEqual(received, [{
    type: 'VKWebAppDeviceMotionChanged',
    data: { alpha: 0.1, beta: -0.2, gamma: 0.3 }
  }]);
  registry.dispose();
});

test('device motion rejects invalid refresh rates before subscribing', async () => {
  const load = createLoader();
  const { VkDeviceMotionHandler } = load('main/ets/vendors/vk/handlers/VkDeviceMotionHandler');
  const { VkBridgeProtocol } = load('main/ets/vendors/vk/VkBridgeProtocol');
  let starts = 0;
  const handler = new VkDeviceMotionHandler({ id: 'device-motion', vendorId: 'vk',
    getDocumentId: () => 1, addCleanup() {}, send: async () => true }, {
    start() { starts++; }, stop() {}
  });

  for (const refresh_rate of [19, 1001, 20.5, '20', null]) {
    await assert.rejects(handler.start({ refresh_rate }), error => {
      assert.equal(VkBridgeProtocol.failure('Failed', 1, error).data.error_data.error_code, 5);
      return true;
    });
  }
  assert.equal(starts, 0);
});

test('device motion cleanup stops the source and suppresses callbacks after a page change', async () => {
  const load = createLoader();
  const { VkDeviceMotionHandler } = load('main/ets/vendors/vk/handlers/VkDeviceMotionHandler');
  let listener;
  let cleanup;
  let stops = 0;
  let sends = 0;
  const context = { id: 'device-motion', vendorId: 'vk', getDocumentId: () => 1,
    addCleanup(fn) { cleanup = fn; }, send: async () => { sends++; return true; } };
  const handler = new VkDeviceMotionHandler(context, {
    start(_rate, next) { listener = next; }, stop() { stops++; }
  });

  await handler.start({ refresh_rate: 20 });
  cleanup();
  listener({ alpha: 1, beta: 2, gamma: 3 });

  assert.equal(stops, 1);
  assert.equal(sends, 0);
});

test('device motion stop is idempotent and suppresses stale callbacks', async () => {
  const load = createLoader();
  const { VkDeviceMotionHandler } = load('main/ets/vendors/vk/handlers/VkDeviceMotionHandler');
  let listener;
  let stops = 0;
  let sends = 0;
  const handler = new VkDeviceMotionHandler({ id: 'device-motion', vendorId: 'vk',
    getDocumentId: () => 1, addCleanup() {}, send: async () => { sends++; return true; } }, {
    start(_rate, next) { listener = next; }, stop() { stops++; }
  });

  await handler.start({ refresh_rate: 20 });
  assert.deepEqual(await handler.stop({}), { result: true });
  assert.deepEqual(await handler.stop({}), { result: true });
  listener({ alpha: 1, beta: 2, gamma: 3 });

  assert.equal(stops, 1);
  assert.equal(sends, 0);
});
