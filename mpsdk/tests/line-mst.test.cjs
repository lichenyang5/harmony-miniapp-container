const assert = require('node:assert/strict');
const { test } = require('node:test');
const crypto = require('node:crypto');
const vm = require('node:vm');
const { createLoader } = require('./sdk-loader.cjs');

function fixture(confirmed = true) {
  class PlatformURL extends URL { get params() { return this.searchParams; } }
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
  const { LineVendor } = load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const vendor = new LineVendor();
  const session = new MiniAppSession('mst-test', {
    info: { appId: 'target-app', vendor: 'line', url: 'https://liff.line.me/target-app' },
    vendor, adapter: new LineAdapter({ mode: 'client' }), swipeBackController: { dispose() {} }
  }, {});
  session.attach({ evaluate: async () => '', pauseAllMedia() {} });
  const binding = session.getBinding();
  const confirm = () => session.interceptWebScheme({ url: 'liff://app/target-app?feature_token=feature',
    isMainFrame: true, documentId: session.getDocumentId() });
  if (confirmed) confirm();
  return { session, binding, confirm };
}

test('MST challenge exists for issuance but storage injection waits for confirmed LIFF identity', () => {
  const f = fixture(false);
  const pair = f.binding.getModalSessionToken();
  assert.ok(pair.challenge);
  assert.deepEqual(f.binding.scripts, []);
  f.confirm();
  assert.equal(f.binding.scripts.length, 1);
  assert.deepEqual(f.binding.getModalSessionToken(), pair);
  f.session.close();
});

function page(script, values = new Map(), isTop = true) {
  const window = { location: { protocol: 'https:' } };
  window.top = isTop ? window : {};
  const sessionStorage = {
    setItem: (key, value) => values.set(key, value),
    getItem: key => values.get(key) ?? null
  };
  vm.runInNewContext(script, { window, sessionStorage, console });
  return values;
}

test('LINE MST follows APK UUID/Base64URL/S256 generation and keeps verifier native', () => {
  const { binding } = fixture();
  const token = binding.getModalSessionToken();
  assert.match(Buffer.from(token.verifier, 'base64url').toString(),
    /^[0-9a-f-]{36}-[0-9a-f-]{36}$/);
  assert.equal(token.challenge, crypto.createHash('sha256').update(token.verifier).digest('base64url'));
  assert.match(token.challenge, /^[\w-]{43}$/);
  const script = binding.scripts[0].script;
  assert.equal(script.includes(token.verifier), false);
  assert.equal(binding.injections[0].methods.includes('getModalSessionToken'), false);
  token.verifier = 'mutated';
  assert.notEqual(binding.getModalSessionToken().verifier, 'mutated');
});

test('LINE MST is available before SDK startup in direct and redirected documents; refresh preserves it', () => {
  const { binding, session } = fixture();
  const script = binding.scripts[0].script;
  const key = 'LIFF_STORE:target-app:mstChallenge';
  for (const address of ['https://liff.line.me/target-app', 'https://access.line.me/login', 'https://example.com/endpoint']) {
    session.beginDocument(address);
    const storage = page(script);
    assert.equal(JSON.parse(storage.get(key)), binding.getModalSessionToken().challenge);
    storage.set('other-app-key', 'keep');
    storage.set(key, '"stale"');
    page(script, storage);
    assert.equal(JSON.parse(storage.get(key)), binding.getModalSessionToken().challenge);
    assert.equal(storage.get('other-app-key'), 'keep');
  }
  assert.equal(page(script, new Map(), false).size, 0);
});

test('LINE MST is isolated for the same app and cleared on disposal', () => {
  const a = fixture(); const b = fixture();
  assert.notEqual(a.binding.getModalSessionToken().challenge, b.binding.getModalSessionToken().challenge);
  const bToken = b.binding.getModalSessionToken();
  a.session.close(); a.session.close();
  assert.equal(a.binding.getModalSessionToken(), undefined);
  assert.deepEqual(a.binding.scripts, []);
  assert.deepEqual(b.binding.getModalSessionToken(), bToken);
});

test('LINE MST storage failure does not interrupt host scripts', () => {
  const { binding } = fixture();
  const window = { location: { protocol: 'https:' } }; window.top = window;
  assert.doesNotThrow(() => vm.runInNewContext(binding.scripts[0].script, {
    window, sessionStorage: { setItem() { throw new Error('denied'); } }, console: { warn() {} }
  }));
});
