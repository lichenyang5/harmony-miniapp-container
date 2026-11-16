const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('gyroscope start uses the default rate and delivers three-axis readings', async () => {
  const load = createLoader();
  const { VkGyroscopeHandler } = load('main/ets/vendors/vk/handlers/VkGyroscopeHandler');
  const { VkEventRegistry } = load('main/ets/vendors/vk/events/VkEventRegistry');
  let listener;
  const rates = [];
  const received = [];
  const context = {
    id: 'gyroscope', vendorId: 'vk', getDocumentId: () => 1, addCleanup() {},
    async send(script) {
      new Function('window', script)({ atomicBridge: { postEvent(data) { received.push(data); } } });
      return true;
    }
  };
  const source = {
    start(rate, next) { rates.push(rate); listener = next; },
    stop() {}
  };
  const handler = new VkGyroscopeHandler(context, source);
  const registry = new VkEventRegistry(context);
  registry.initHandler([handler]);
  assert.ok(registry.getHandler('VKWebAppGyroscopeStart'));
  assert.ok(registry.getHandler('VKWebAppGyroscopeStop'));

  assert.deepEqual(await handler.start({}), { result: true });
  assert.deepEqual(rates, [1000]);
  listener({ x: -0.1, y: 0, z: 4.5 });
  await Promise.resolve();

  assert.deepEqual(received, [{ type: 'VKWebAppGyroscopeChanged', data: { x: -0.1, y: 0, z: 4.5 } }]);
  registry.dispose();
});

test('gyroscope rejects invalid refresh rates before subscribing', async () => {
  const load = createLoader();
  const { VkGyroscopeHandler } = load('main/ets/vendors/vk/handlers/VkGyroscopeHandler');
  const { VkBridgeProtocol } = load('main/ets/vendors/vk/VkBridgeProtocol');
  let starts = 0;
  const handler = new VkGyroscopeHandler({ id: 'gyroscope', vendorId: 'vk', getDocumentId: () => 1,
    addCleanup() {}, send: async () => true }, { start() { starts++; }, stop() {} });

  for (const refresh_rate of [19, 1001, 20.5, '20', null]) {
    await assert.rejects(handler.start({ refresh_rate }), error => {
      assert.equal(VkBridgeProtocol.failure('Failed', 1, error).data.error_data.error_code, 5);
      return true;
    });
  }
  assert.equal(starts, 0);
});

test('gyroscope stop and disposal stop one subscription and suppress stale callbacks', async () => {
  const load = createLoader();
  const { VkGyroscopeHandler } = load('main/ets/vendors/vk/handlers/VkGyroscopeHandler');
  let listener;
  let stops = 0;
  let sends = 0;
  const handler = new VkGyroscopeHandler({ id: 'gyroscope', vendorId: 'vk', getDocumentId: () => 1,
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
