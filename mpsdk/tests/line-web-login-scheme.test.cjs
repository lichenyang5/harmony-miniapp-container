const { test } = require('node:test');
const assert = require('node:assert/strict');
const { fixture, deferred, tick } = require('./fixtures/line-web-login-fixture.cjs');
test('supports is pure and matches official top-frame OAuth only', async () => {
  const f = fixture();
  for (const url of [f.url, 'https://access.line.me/dialog/oauth/weblogin']) assert.equal(f.handler.supports({ url, isMainFrame: true }), true);
  for (const [url, isMainFrame] of [[f.url, false], ['http://access.line.me/oauth2/v2.1/login', true],
    ['https://access.line.me.evil.example/oauth2/v2.1/login', true], ['https://user@access.line.me/oauth2/v2.1/login', true],
    ['https://access.line.me:8443/oauth2/v2.1/login', true], ['https://access.line.me/other', true]]) {
    assert.equal(f.handler.supports({ url, isMainFrame }), false);
  }
  assert.equal(f.calls.length, 0); f.results.push({ returnUrl: 'https://shop.example/callback' });
  f.dispatch(); await tick(); assert.equal(f.calls[0].input.hookedFullUrl, f.url);
});
test('reset drops late errors and disposed handler proceeds', async () => {
  const f = fixture(), pending = deferred(); f.results.push(pending.promise); f.dispatch();
  f.handler.reset(); pending.reject(Error('old')); await tick(); assert.deepEqual(f.failures, []);
  f.handler.dispose(); assert.equal(f.handler.handle({ url: f.url, isMainFrame: true }, { proceed: () => 42 }), 42);
});

test('LIFF OAuth reads shared state at transaction start and pins that identity across consent rounds', async () => {
  const f = fixture();
  f.appState.current = { liffId: 'issued-before-start', featureToken: 'feature' };
  f.results.push({ consentUrl: 'https://access.line.me/consent', sessionString: 's' },
    { returnUrl: 'https://shop.example/callback' });
  f.dispatch(); await tick();
  f.appState.current = { liffId: 'later-state', featureToken: 'later-feature' };
  f.pages[0].resolve(true); await tick();
  assert.deepEqual(f.calls.map(request => request.liffId), ['issued-before-start', 'issued-before-start']);
  assert.deepEqual(f.failures, []);
  f.dispatcher.dispose();
});

test('missing LIFF state cannot start OAuth while browser OAuth remains independent of app state', async () => {
  for (const source of ['liff', 'browser']) {
    const f = fixture(source);
    f.appState.current = undefined;
    f.results.push({ returnUrl: 'https://shop.example/callback' });
    f.dispatch(); await tick();
    assert.equal(f.calls.length, source === 'liff' ? 0 : 1);
    assert.deepEqual(f.failures.map(error => error.code), source === 'liff' ? ['LINE_WEB_LOGIN_FAILED'] : []);
    f.dispatcher.dispose();
  }
});
