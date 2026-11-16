const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const { WebSchemeDecision: D } = createLoader()('main/ets/web/scheme/WebSchemeTypes');
const { fixture, tick, deferred } = require('./fixtures/line-web-login-fixture.cjs');

test('approval preserves original URL, server session and native headers', async () => {
  const f = fixture();
  f.results.push({ consentUrl: 'https://access.line.me/consent', sessionString: 'server-session' },
    { returnUrl: 'https://shop.example/callback?code=opaque' });
  f.dispatch(); await tick();
  assert.equal(f.pages[0].page.headers['X-Line-Access'], 'native-token');
  assert.match(f.pages[0].page.url, /sessionString=server-session/);
  f.pages[0].resolve(true); await tick();
  assert.deepEqual(f.calls.map(c => c.allowed), [true, true]);
  assert.equal(f.calls[1].input.sessionString, 'server-session');
  assert.equal(f.calls[1].input.hookedFullUrl, f.url);
  assert.deepEqual(f.resumed, [['https://shop.example/callback?code=opaque&mst_challenge=prepared', 1, true]]);
  assert.equal(f.listeners.size, 0); assert.deepEqual(f.failures, []);
});
test('denial calls disallowed, invalidation and account replacement discard results', async () => {
  for (const action of ['deny', 'invalidate', 'replace']) {
    const f = fixture(); f.results.push({ consentUrl: 'https://access.line.me/consent', sessionString: 's' },
      { returnUrl: 'https://shop.example/callback?error=access_denied' });
    f.dispatch(); await tick();
    if (action === 'invalidate') f.invalidate();
    else { if (action === 'replace') f.replaceAccount(); f.pages[0].resolve(false); }
    await tick();
    assert.deepEqual(f.calls.map(c => c.allowed), action === 'deny' ? [true, false] : [true]);
    assert.equal(f.resumed.length, action === 'deny' ? 1 : 0); assert.deepEqual(f.failures, []);
  }
});
test('deduplication and late RPC cannot cross document boundaries', async () => {
  const f = fixture(), pending = deferred(); f.results.push(pending.promise);
  f.dispatch(); f.dispatch(); assert.equal(f.calls.length, 1);
  f.dispatch(f.url + 'other'); assert.equal(f.failures[0].code, 'LINE_CONSENT_BUSY');
  f.navigate(); pending.resolve({ returnUrl: 'https://shop.example/callback' }); await tick();
  assert.equal(f.resumed.length, 0); assert.equal(f.failures.length, 1);
});
test('unchanged consent cannot loop and browser generates one session', async () => {
  const f = fixture('browser'), consent = { consentUrl: 'https://access.line.me/consent' };
  f.results.push(consent, consent); f.dispatch(); await tick(); f.pages[0].resolve(true); await tick();
  assert.equal(f.pages.length, 1); assert.equal(f.failures[0].code, 'LINE_WEB_LOGIN_NO_PROGRESS');
  assert.equal(new URL(f.pages[0].page.url).searchParams.get('sessionString'), f.calls[1].input.sessionString);
  assert.match(f.calls[1].input.sessionString, /^uuid-/);
});
test('LIFF temporary fallback and background account guard', async () => {
  const f = fixture(); f.results.push({ consentUrl: 'https://access.line.me/consent' }, { returnUrl: 'https://shop.example/done' });
  f.dispatch(); await tick(); const session = new URL(f.pages[0].page.url).searchParams.get('sessionString');
  assert.match(session, /^uuid-/); f.pages[0].resolve(true); await tick();
  assert.equal(f.calls[1].input.sessionString, session);
  f.background(); f.dispatch(); assert.equal(f.calls.length, 2);
});
test('only exact prepared URL is granted once, including MST and fragment', async () => {
  for (const change of [url => url.replace('prepared', 'other'), url => url + '&extra=1', url => url + '#other']) {
    const f = fixture(); f.results.push({ returnUrl: 'https://access.line.me/dialog/oauth/weblogin?requestToken=once' });
    f.dispatch(); await tick(); const target = f.resumed[0][0];
    assert.equal(f.dispatch(change(target)), D.CONSUME); f.handler.reset(); await tick();
  }
  const exact = fixture(); exact.results.push({ returnUrl: 'https://access.line.me/dialog/oauth/weblogin?requestToken=once' });
  exact.dispatch(); await tick(); const granted = exact.resumed[0][0];
  assert.equal(exact.dispatch(granted), D.PASS); assert.equal(exact.dispatch(granted), D.CONSUME); exact.handler.reset(); await tick();
  const f = fixture(); f.results.push({ returnUrl: 'https://access.line.me/dialog/oauth/weblogin?requestToken=once' });
  f.dispatch(); await tick(); const target = f.resumed[0][0]; f.replaceAccount();
  assert.equal(f.dispatch(target), D.CONSUME); f.handler.reset(); await tick();
});
test('old failure cannot clear newer operation or show late error', async () => {
  const f = fixture(), old = deferred(), current = deferred(); f.results.push(old.promise, current.promise);
  f.dispatch(); f.navigate(); f.dispatch(); old.reject(Error('old network')); await tick();
  f.dispatch(); assert.equal(f.calls.length, 2); assert.deepEqual(f.failures, []);
  current.resolve({ returnUrl: 'https://shop.example/new' }); await tick(); assert.equal(f.resumed.length, 1);
});
test('current failures report once and disposal cancels consent', async () => {
  const f = fixture(); f.results.push(Error('network')); f.dispatch(); await tick();
  assert.equal(f.failures.length, 1); assert.equal(f.listeners.size, 0); assert.equal(f.resumed.length, 0);
  f.results.push({ consentUrl: 'https://access.line.me/consent' }); f.dispatch(); await tick();
  f.handler.dispose(); f.handler.dispose(); await tick();
  assert.equal(f.failures.length, 1); assert.equal(f.listeners.size, 0);
});


test('handler reads the account at transaction start and drops a reply after owner goes background', async () => {
  const f = fixture(); f.host.account = undefined; f.dispatch();
  assert.equal(f.failures[0].code, 'LINE_ACCOUNT_PROVIDER_REQUIRED'); assert.equal(f.calls.length, 0);
  f.host.account = f.account;
  const pending = deferred(); f.results.push(pending.promise); f.dispatch();
  assert.equal(f.calls.length, 1); f.background(); pending.resolve({ returnUrl: 'https://shop.example/done' });
  await tick(); assert.equal(f.resumed.length, 0); assert.equal(f.failures.length, 1); assert.equal(f.listeners.size, 0);
});
