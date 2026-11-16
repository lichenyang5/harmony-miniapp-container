const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const tick = () => new Promise(resolve => setImmediate(resolve));
const load = createLoader();
const { WebSchemeDispatcher } = load('main/ets/web/scheme/WebSchemeDispatcher');
const { WebSchemeDecision: D } = load('main/ets/web/scheme/WebSchemeTypes');
const sample = 'line://app/2006593963-DPoAqdzG?liff.source=lp_link&liff.via=lp_link';

function fixture(openMiniApp = async () => {}) {
  const { LineBrowserAppSchemeHandler } = load('main/ets/vendors/line/scheme/LineBrowserAppSchemeHandler');
  let active = true, failures = 0;
  const calls = [];
  const handler = new LineBrowserAppSchemeHandler({
    isActive: () => active,
    async openMiniApp(app) { calls.push(app); await openMiniApp(app); },
    onFailure() { failures++; }
  });
  const dispatcher = new WebSchemeDispatcher([handler]);
  return { calls, dispatcher, get failures() { return failures; }, hide() { active = false; },
    dispatch: (url = sample, isMainFrame = true) => dispatcher.dispatch({ url, isMainFrame }) };
}

test('browser LINE app deep links use the shared dispatcher and preserve the original query', async () => {
  const f = fixture();
  assert.equal(f.dispatch(), D.CONSUME); await tick();
  assert.deepEqual(f.calls, [{ appId: '2006593963-DPoAqdzG', vendor: 'line',
    url: 'https://liff.line.me/2006593963-DPoAqdzG?liff.source=lp_link&liff.via=lp_link' }]);
  const tail = '?liff.state=%2Ffoo%3Fx%3D1&x=%252F&x=2';
  assert.equal(f.dispatch('LINE://app/%31%32%33-App' + tail), D.CONSUME); await tick();
  assert.equal(f.calls[1].appId, '123-App');
  assert.equal(f.calls[1].url, 'https://liff.line.me/%31%32%33-App' + tail);
});

test('subframes, hidden views and malformed app targets cannot launch mini apps', () => {
  const f = fixture();
  assert.equal(f.dispatch(sample, false), D.BLOCK);
  for (const value of ['line://app', 'line://app/', 'line://app/a/b', 'line://app/%2Fbad', 'line://app/%ZZ',
    'line://app/a\nb', 'line://app/a b']) {
    assert.equal(f.dispatch(value), D.BLOCK, value);
  }
  for (const value of ['https://example.test', 'line://app.evil/123-App', 'line://user@app/123-App',
    'line://app:443/123-App', 'line://APP/123-App', 'line://other/123-App']) {
    assert.equal(f.dispatch(value), D.PASS, value);
  }
  f.hide(); assert.equal(f.dispatch(), D.BLOCK); assert.deepEqual(f.calls, []);
});

test('pending launches reject duplicate navigation and host failures allow an explicit retry', async () => {
  let reject;
  const f = fixture(() => new Promise((_resolve, fail) => { reject = fail; }));
  assert.equal(f.dispatch(), D.CONSUME); assert.equal(f.dispatch(), D.BLOCK);
  assert.equal(f.calls.length, 1);
  reject(Error('private cause')); await tick();
  assert.equal(f.failures, 1);
  assert.equal(f.dispatch(), D.CONSUME); reject(Error('second')); await tick();
  assert.equal(f.calls.length, 2);
});

test('reset and disposal discard late error UI without cancelling an accepted host operation', async () => {
  let reject;
  const f = fixture(() => new Promise((_resolve, fail) => { reject = fail; }));
  f.dispatch(); f.dispatcher.reset(); reject(Error('old document')); await tick();
  assert.equal(f.failures, 0);
  f.dispatch(); f.dispatcher.dispose(); reject(Error('closed')); await tick();
  assert.equal(f.failures, 0); assert.equal(f.dispatch(), D.BLOCK);
});
