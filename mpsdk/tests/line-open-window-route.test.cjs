const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
class PlatformURL extends URL { get params() { return this.searchParams; } }
const createRouteLoader = () => createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
  { '@kit.ArkTS': { url: { URL: PlatformURL } } });

test('shared LIFF resolver preserves raw ID and state encoding without vendor configuration', () => {
  const load = createRouteLoader();
  const { resolveLineLiffUrl } = load('main/ets/vendors/line/liff/LineLiffUrl');
  const { validateLineBrowserUrl } = load('main/ets/vendors/line/browser/LineBrowserUrl');
  for (const host of ['liff.line.me', 'miniapp.line.me']) {
    const address = `https://${host}///id%2Fpart/a/%2e%2e/b?x=%252F&x=2#frag%20ment`;
    const target = resolveLineLiffUrl(address, validateLineBrowserUrl(address));
    assert.deepEqual(Object.keys(target).sort(), ['appId', 'url']);
    assert.equal(target.appId, 'id/part');
    assert.equal(target.url, `https://${host}/id%2Fpart?liff.state=` +
      encodeURIComponent('/a/%2e%2e/b?x=%252F&x=2#frag%20ment'));
  }
  for (const address of ['https://liff.line.me///?x=1', 'https://miniapp.line.me',
    'http://liff.line.me/123', 'https://liff.line.me.evil/123', 'https://example.test/123']) {
    assert.equal(resolveLineLiffUrl(address, validateLineBrowserUrl(address)), undefined, address);
  }
  const malformed = 'https://liff.line.me/%zz/a';
  assert.throws(() => resolveLineLiffUrl(malformed, validateLineBrowserUrl(malformed)),
    { code: 'INVALID_ARGUMENT' });
});

// Exercise routing through the real Handler instead of exposing its private resolver.
async function resolve(address, external) {
  const load = createRouteLoader();
  const { LineOpenWindowHandler } = load('main/ets/vendors/line/handlers/LineOpenWindowHandler');
  let route;
  const { LineBrowserHost } = load('main/ets/vendors/line/browser/LineBrowserHost');
  LineBrowserHost.prototype.open = async url => { route = { kind: 'browser', url }; };
  const handler = new LineOpenWindowHandler({
    getDocumentId: () => 1, addCleanup() {},
    async requestOpenMiniApp(app) { route = { kind: 'liff', url: app.url, appId: app.appId }; }
  }, new LineBrowserHost({}));
  try {
    await handler.handle({ url: address, external }, {});
    return route;
  } finally {
    handler.dispose();
  }
}

test('route recognizes exact HTTPS LIFF hosts and preserves state bytes', async () => {
  for (const host of ['liff.line.me', 'miniapp.line.me']) {
    const route = await resolve(`https://${host}/123/a%2Fb?x=%252F&x=2#frag%20ment`, false);
    assert.equal(route.kind, 'liff');
    assert.equal(route.appId, '123');
    const target = new URL(route.url);
    assert.equal(target.origin, `https://${host}`);
    assert.equal(target.pathname, '/123');
    assert.equal(target.searchParams.get('liff.state'), '/a%2Fb?x=%252F&x=2#frag%20ment');
    assert.equal((await resolve(`https://${host}/123//other.test/x`, false)).kind, 'liff');
  }
  for (const address of ['https://liff.line.me/', 'https://liff.line.me',
    'http://liff.line.me/123', 'https://liff.line.me.evil/123', 'https://example.test/123']) {
    assert.equal((await resolve(address, false)).kind, 'browser', address);
  }
});

test('external takes precedence and ordinary pages use the browser route', async () => {
  assert.equal((await resolve('https://liff.line.me/123', true)).kind, 'browser');
  assert.equal((await resolve('https://liff.line.me/%zz/a', true)).kind, 'browser');
  await assert.rejects(resolve('https://liff.line.me/%zz/a', false),
    error => error.toData().code === 'INVALID_ARGUMENT');
  assert.equal((await resolve('https://liff.line.me/123?openExternalBrowser=1', false)).kind, 'liff');
  for (const value of ['1', 'true']) {
    assert.equal((await resolve(`https://example.test/?openExternalBrowser=${value}`, false)).kind, 'browser');
  }
  for (const value of ['TRUE', 'True', '0']) {
    assert.equal((await resolve(`https://example.test/?openExternalBrowser=${value}`, false)).kind, 'browser');
  }
  for (const address of ['', 'tel:+123', 'mailto:me@example.test', '  https://example.test', 'javascript:alert(1)', 'data:text/html,x',
    'file:///tmp/a', 'content://a', 'intent://a', 'custom://a', 'https://user:pass@example.test']) {
    await assert.rejects(resolve(address, false), error => error.toData().code === 'INVALID_ARGUMENT', address);
  }
});

test('LIFF state preserves unnormalized encoded paths and empty query/fragment delimiters', async () => {
  for (const state of ['/a/%2e%2e/b?x=%2f#f', '/a/../b?x=1&x=2#f', '/a?#', '?', '#']) {
    const route = await resolve(`https://liff.line.me/123${state}`, false);
    assert.equal(new URL(route.url).searchParams.get('liff.state'), state);
  }
});

test('LIFF IDs decode the first nonempty segment while the target path retains its encoding', async () => {
  for (const prefix of ['/', '//', '///']) {
    const route = await resolve(`https://miniapp.line.me${prefix}123//a?x=1`, false);
    assert.equal(route.kind, 'liff');
    assert.equal(route.appId, '123');
    assert.equal(new URL(route.url).pathname, '/123');
    assert.equal(new URL(route.url).searchParams.get('liff.state'), '//a?x=1');
  }
  const encoded = await resolve('https://liff.line.me/id%2Fpart/a', false);
  assert.equal(encoded.appId, 'id/part');
  assert.equal(new URL(encoded.url).pathname, '/id%2Fpart');
  assert.equal((await resolve('https://liff.line.me/%31%32%33/a', false)).appId, '123');
  assert.equal((await resolve('https://liff.line.me///?x=1', false)).kind, 'browser');
});


test('APK wraps existing state queries and fragments as the remaining link content', async () => {
  for (const host of ['liff.line.me', 'miniapp.line.me']) {
    for (const query of ['?liff.state=%2Fdetail%3Fid%3D7',
      '?x=one&liff.state=%2Fa%252Fb%3Fx%3D%252F&x=two#raw%2Ffragment',
      '?liff%2Estate=%2Fdetail', '?liff.state=&x=1', '?liff.state']) {
      for (const suffix of ['', '/']) {
        const route = await resolve('https://' + host + '/app-id' + suffix + query, false);
        assert.equal(route.kind, 'liff');
        assert.equal(route.appId, 'app-id');
        assert.equal(route.url, 'https://' + host + '/app-id?liff.state=' + encodeURIComponent(query));
      }
    }
  }
});


test('APK only removes a lone slash or the slash before a leading query or fragment', async () => {
  for (const [tail, state] of [
    ['', null], ['/', null], ['/?x=1', '?x=1'], ['/#fragment', '#fragment'],
    ['/?', '?'], ['/#', '#'], ['//?x=1', '//?x=1'], ['//', '//'],
    ['/detail/?x=1', '/detail/?x=1'],
    ['?liff.state=A&liff.state=B', '?liff.state=A&liff.state=B'],
    ['/detail?liff.state=%2Fother', '/detail?liff.state=%2Fother']
  ]) {
    const route = await resolve('https://liff.line.me/app-id' + tail, false);
    const result = new URL(route.url);
    assert.equal(result.pathname, '/app-id', tail);
    assert.equal(result.searchParams.get('liff.state'), state, tail);
  }
});
