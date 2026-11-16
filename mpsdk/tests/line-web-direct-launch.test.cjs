const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');

const { createLineWebDirectLaunchScript } = createLoader()(
  'main/ets/vendors/line/script/LineWebDirectLaunch');
const script = createLineWebDirectLaunchScript().script;
const target = 'https://example.com/miniapp?liff.source=lp_link&liff.via=lp_link';

function page(hostname, { frame = false, info, link } = {}) {
  const redirects = [];
  const window = {};
  window.top = frame ? {} : window;
  if (info) window.liffInfo = info;
  const context = vm.createContext({
    window,
    location: {
      hostname, href: `https://${hostname}/2008122305-6NoqBGpY`,
      replace(url) { redirects.push(url); }
    },
    document: {
      getElementById(id) { return id === 'linkOpenInBrowserLink' ? link : null; },
      addEventListener() {}
    },
    MutationObserver: class { observe() {} disconnect() {} },
    console: { info() {}, warn() {} },
    URL,
    setTimeout() {}
  });
  vm.runInContext(script, context);
  return { window, context, redirects };
}

for (const hostname of ['miniapp.line.me', 'liff.line.me']) {
  test(`${hostname} redirects when the guide assigns liffInfo, without duplicate navigation`, () => {
    const p = page(hostname);
    assert.deepEqual(p.redirects, []);
    p.window.liffInfo = { liffAppUrlForBrowser: target };
    assert.deepEqual(p.redirects, [target]);
    vm.runInContext(script, p.context);
    assert.deepEqual(p.redirects, [target]);
  });

  test(`${hostname} supports existing guide config and the browser link fallback`, () => {
    assert.deepEqual(page(hostname, { info: { liffAppUrlForBrowser: target } }).redirects, [target]);
    const link = { tagName: 'A', getAttribute: () => target };
    assert.deepEqual(page(hostname, { link }).redirects, [target]);
  });

  test(`${hostname} ignores iframe guides and non-HTTPS targets`, () => {
    const info = { liffAppUrlForBrowser: target };
    assert.deepEqual(page(hostname, { frame: true, info }).redirects, []);
    for (const value of ['http://example.com/', 'javascript:alert(1)', 'line://app/id']) {
      assert.deepEqual(page(hostname, { info: { liffAppUrlForBrowser: value } }).redirects, []);
    }
  });
}

test('non-guide hosts, including login and lookalike hosts, are untouched', () => {
  for (const hostname of ['access.line.me', 'example.com', 'liff.line.me.example.com']) {
    const info = { liffAppUrlForBrowser: target };
    const p = page(hostname, { info });
    assert.deepEqual(p.redirects, []);
    assert.equal(p.window.__atomicLineWebDirectLaunch, undefined);
    assert.equal(p.window.liffInfo, info);
  }
});
