const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('accelerometer start normalizes the default rate and delivers readings to the mini app', async () => {
  const load = createLoader();
  const { VkAccelerometerHandler } = load('main/ets/vendors/vk/handlers/VkAccelerometerHandler');
  const { VkEventRegistry } = load('main/ets/vendors/vk/events/VkEventRegistry');
  let listener;
  const rates = [];
  const received = [];
  const context = {
    id: 'accelerometer', vendorId: 'vk', getDocumentId: () => 1, addCleanup() {},
    async send(script) {
      new Function('window', script)({ atomicBridge: { postEvent(data) { received.push(data); } } });
      return true;
    }
  };
  const source = {
    start(rate, next) { rates.push(rate); listener = next; },
    stop() {}
  };
  const handler = new VkAccelerometerHandler(context, source);
  const registry = new VkEventRegistry(context);
  registry.initHandler([handler]);
  assert.ok(registry.getHandler('VKWebAppAccelerometerStart'));
  assert.ok(registry.getHandler('VKWebAppAccelerometerStop'));

  assert.deepEqual(await handler.start({}), { result: true });
  assert.deepEqual(rates, [1000]);
  listener({ x: 1.25, y: -2, z: 0 });
  await Promise.resolve();

  assert.deepEqual(received, [{ type: 'VKWebAppAccelerometerChanged', data: { x: 1.25, y: -2, z: 0 } }]);
  registry.dispose();
});

test('accelerometer rejects a non-integer or out-of-range refresh rate before subscribing', async () => {
  const load = createLoader();
  const { VkAccelerometerHandler } = load('main/ets/vendors/vk/handlers/VkAccelerometerHandler');
  const { VkBridgeProtocol } = load('main/ets/vendors/vk/VkBridgeProtocol');
  let starts = 0;
  const handler = new VkAccelerometerHandler({ id: 'accelerometer', vendorId: 'vk', getDocumentId: () => 1,
    addCleanup() {}, send: async () => true }, {
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

test('accelerometer stop and disposal stop the source and suppress stale sensor callbacks', async () => {
  const load = createLoader();
  const { VkAccelerometerHandler } = load('main/ets/vendors/vk/handlers/VkAccelerometerHandler');
  let listener;
  let stops = 0;
  let sends = 0;
  const handler = new VkAccelerometerHandler({ id: 'accelerometer', vendorId: 'vk', getDocumentId: () => 1,
    addCleanup() {}, send: async () => { sends++; return true; } }, {
    start(_rate, next) { listener = next; }, stop() { stops++; }
  });

  await handler.start({ refresh_rate: 20 });
  assert.deepEqual(await handler.stop({}), { result: true });
  listener({ x: 1, y: 2, z: 3 });
  handler.dispose();
  handler.dispose();
  listener({ x: 4, y: 5, z: 6 });

  assert.equal(stops, 1);
  assert.equal(sends, 0);
});
