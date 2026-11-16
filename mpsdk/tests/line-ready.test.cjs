const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');

function fixture() {
  const load = createLoader();
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const vendor = new LineVendor();
  const window = { _liff: {} };
  const events = [];
  const installSdk = () => {
    window.liff = { _dispatchEvent(json) {
      const event = JSON.parse(json);
      assert.deepEqual(JSON.parse(JSON.stringify(window._liff.features)), event.data.features);
      events.push(event);
    } };
  };
  const session = new MiniAppSession('ready-test', {
    info: { appId: 'app', vendor: 'line', url: 'https://example.com/' },
    vendor, adapter: new LineAdapter({ mode: 'client' }), swipeBackController: { dispose() {} }
  }, {});
  const scripts = [];
  session.attach({ evaluate(script) {
    scripts.push(script);
    vm.runInNewContext(script, { window });
    return Promise.resolve('');
  } });
  return { session, window, events, scripts, installSdk };
}

test('LINE ready is sent only on current page completion, after attributes are set', () => {
  const f = fixture(); f.installSdk();
  assert.equal(f.scripts.length, 0);
  f.session.beginDocument('https://example.com/');
  assert.equal(f.scripts.length, 0);
  f.session.finishDocument('https://example.com/');
  assert.deepEqual(f.events, [{ type: 'ready', callbackId: '', data: { features: ['closeWindow', 'scanCode', 'openWindow'], scopes: [] } }]);
  f.session.finishDocument('https://example.com/');
  assert.equal(f.events.length, 1);
});

test('late SDK sees features; blank, stale page and closed session do not send ready', () => {
  const f = fixture();
  f.session.beginDocument('about:blank');
  f.session.finishDocument('about:blank');
  assert.equal(f.scripts.length, 0);
  f.session.beginDocument('https://example.com/');
  f.session.finishDocument('https://example.com/');
  assert.equal(Array.isArray(f.window._liff.features), true);
  assert.equal(f.events.length, 0);
  f.installSdk();
  f.session.beginDocument('https://example.com/next');
  f.session.finishDocument('https://example.com/');
  assert.equal(f.scripts.length, 1);
  f.session.finishDocument('https://example.com/next');
  assert.equal(f.events.length, 1);
  f.session.beginDocument('https://example.com/next');
  f.session.finishDocument('https://example.com/next');
  assert.equal(f.events.length, 2);
  f.session.close();
  f.session.finishDocument('https://example.com/next');
  assert.equal(f.events.length, 2);
});
