function createTestSession(load, { id = 'test-session', appId = 'same-app', host,
  onScript = () => {}, adapter } = {}) {
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { VkVendor } = load('main/ets/vendors/vk/VkVendor');
  const { VkAdapter } = load('main/ets/vendors/vk/VkAdapter');
  const session = new MiniAppSession(id, {
    info: { appId, vendor: 'vk', url: 'https://vk.ru/app1' }, vendor: new VkVendor(),
    adapter: adapter || new VkAdapter(),
    swipeBackController: { setEnabled() {}, dispose() {} }
  }, host || { applicationInfo: { accessTokenId: 1 } });
  session.attach({ async evaluate(script) { onScript(script); return ''; }, pauseAllMedia() {} });
  session.beginDocument('https://vk.ru/app1');
  return session;
}

module.exports = { createTestSession };
