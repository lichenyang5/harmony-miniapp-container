const listeners = new WeakMap();

// Drive the actual SDK listener through the platform registration boundary.
function applicationLifecycle(load) {
  if (!listeners.has(load)) {
    const { MiniAppSDK } = load('main/ets/core/MiniAppSDK');
    MiniAppSDK.initialize({ on(_event, callback) {
      listeners.set(load, callback);
      return 0;
    } });
  }
  return listeners.get(load);
}

module.exports = { applicationLifecycle };
