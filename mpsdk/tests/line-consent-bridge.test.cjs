const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');

function fixture() {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } } });
  const { LineConsentBridge } = load('main/ets/vendors/line/consent/LineConsentBridge');
  let address = 'https://access.line.me/oauth2/v2.1/authorize/consent';
  let allowed = 0;
  const bridge = new LineConsentBridge(() => address, () => { allowed++; });
  return { bridge, setAddress: value => { address = value; }, get allowed() { return allowed; } };
}

test('official consent success script completes through line.onUserAllowed without a scheme redirect', () => {
  const f = fixture();let load;
  const page = { line: f.bridge, addEventListener: (_name, callback) => { load = callback; },
    setTimeout() { assert.fail('registered native bridge must end the page polling'); } };
  page.window = page;
  const script = fs.readFileSync(path.join(__dirname, 'fixtures/line-consent-allowed.js'), 'utf8');
  vm.runInNewContext(script, page);load();
  assert.equal(f.allowed, 1);
  f.bridge.onUserAllowed();assert.equal(f.allowed, 1);
});

test('untrusted documents and disposed consent bridges cannot complete authorization', () => {
  const f = fixture();
  f.setAddress('https://example.com/');f.bridge.onUserAllowed();assert.equal(f.allowed, 0);
  f.setAddress('https://access.line.me/oauth2/v2.1/authorize/consent');
  f.bridge.dispose();f.bridge.onUserAllowed();assert.equal(f.allowed, 0);
});
