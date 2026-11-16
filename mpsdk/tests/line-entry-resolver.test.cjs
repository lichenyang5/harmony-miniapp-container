const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

class PlatformURL extends URL { get params() { return this.searchParams; } }
const initial = 'https://miniapp.line.me/app-id';
const endpoint = 'https://app.example/liff/?liff.source=lp_link&liff.via=lp_link';
function html(target = endpoint, id = 'app-id') {
  return `<script>let liffFullUrlForBrowser = ${JSON.stringify(target)};
    window.liffInfo = { liffId: ${JSON.stringify(id)} };</script>`;
}
function fixture(respond = async () => ({ responseCode: 200, result: html() })) {
  const clients = [];
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined, {
    '@kit.ArkTS': { url: { URL: PlatformURL } },
    '@kit.NetworkKit': { http: {
      RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 0 },
      createHttp() {
        const client = { destroyed: 0, request: async (address, options) => {
          client.address = address; client.options = options; return respond(address, options);
        }, destroy() { client.destroyed++; } };
        clients.push(client); return client;
      }
    } }
  });
  return { load, clients, create() {
    return new (load('main/ets/vendors/line/LineEntryResolver').LineEntryResolver)();
  } };
}

test('resolves official landing HTML without executing scripts or sending credentials', async () => {
  const f = fixture();
  assert.equal(await f.create().resolve(initial, 'app-id'), endpoint);
  assert.equal(f.clients.length, 1);
  assert.equal(f.clients[0].destroyed, 1);
  assert.match(f.clients[0].options.header['User-Agent'], /Android/);
  assert.deepEqual(Object.keys(f.clients[0].options.header).sort(), ['Accept', 'User-Agent']);
  assert.equal(f.clients[0].options.maxLimit, 1024 * 1024);
});

test('ordinary endpoint and lookalike hosts pass through without HTTP', async () => {
  const f = fixture(); const resolver = f.create();
  for (const address of [endpoint, 'https://miniapp.line.me.evil.example/app-id']) {
    assert.equal(await resolver.resolve(address, 'app-id'), address);
  }
  assert.equal(f.clients.length, 0);
});

test('preserves server-generated path and query, and adds fragment to liff.state', async () => {
  const target = 'https://app.example/liff/?x=1&x=2&liff.state=%2Fdetail%3Fid%3D7';
  const f = fixture(async () => ({ responseCode: 200, result: html(target) }));
  const address = initial.replace('miniapp', 'liff') + '/detail?id=7#section';
  const result = new URL(await f.create().resolve(address, 'app-id'));
  assert.equal(f.clients[0].address, address.split('#')[0]);
  assert.equal(result.searchParams.get('liff.state'), '/detail?id=7#section');
  assert.deepEqual(result.searchParams.getAll('x'), ['1', '2']);
  assert.equal(result.hash, '');
});

test('rejects invalid entry IDs and insecure official URLs before HTTP', async () => {
  const f = fixture();
  for (const address of ['http://miniapp.line.me/app-id', initial + '-other',
    'https://user:pass@miniapp.line.me/app-id', 'https://miniapp.line.me/%ZZ']) {
    await assert.rejects(f.create().resolve(address, 'app-id'), e => e.code === 'LINE_ENTRY_INVALID');
  }
  assert.equal(f.clients.length, 0);
});

test('rejects malformed, ambiguous and mismatched landing pages and invalid targets', async () => {
  for (const result of ['<script>throw new Error("must not execute")</script>', html(endpoint, 'other-id'),
    html('javascript:alert(1)'), html('http://app.example/'), html(initial),
    html('https://liff.line.me/app-id'), html('https://user:pass@app.example/'),
    html() + html(), html().replace(JSON.stringify(endpoint), 'makeUrl()'),
    html().replace(JSON.stringify(endpoint), JSON.stringify(endpoint) + ' + "details"'),
    html().replace(JSON.stringify(endpoint), JSON.stringify(endpoint) + '\n + "details"'),
    html().replace('liffId: "app-id"', 'liffId: "app-id" + "other"')]) {
    const f = fixture(async () => ({ responseCode: 200, result }));
    await assert.rejects(f.create().resolve(initial, 'app-id'), e => e.code === 'LINE_ENTRY_INVALID');
    assert.equal(f.clients[0].destroyed, 1);
  }
});

test('network, non-success HTTP and excessive HTML fail without falling back to guide', async () => {
  for (const respond of [async () => { throw new Error('private network error'); },
    async () => ({ responseCode: 503, result: html() }),
    async () => ({ responseCode: 200, result: new ArrayBuffer(4) }),
    async () => ({ responseCode: 200, result: ' '.repeat(1024 * 1024 + 1) })]) {
    const f = fixture(respond);
    await assert.rejects(f.create().resolve(initial, 'app-id'), e => e.code === 'LINE_ENTRY_RESOLVE_FAILED');
    assert.equal(f.clients[0].destroyed, 1);
  }
});

test('dispose rejects pending resolution promptly and isolates same-app instances', async () => {
  let finish;
  const f = fixture(() => new Promise(resolve => { finish = resolve; }));
  const a = f.create(); const b = f.create();
  const pending = a.resolve(initial, 'app-id');
  a.dispose(); a.dispose();
  await assert.rejects(pending, e => e.code === 'LINE_SESSION_CLOSED');
  finish({ responseCode: 200, result: html() });
  await assert.rejects(a.resolve(initial, 'app-id'), e => e.code === 'LINE_SESSION_CLOSED');
  assert.equal(await b.resolve(endpoint, 'app-id'), endpoint);
  assert.equal(f.clients[0].destroyed, 1);
});

test('total deadline releases request even if the native request never settles', async (t) => {
  let expire;
  t.mock.method(global, 'setTimeout', (callback, milliseconds) => {
    assert.equal(milliseconds, 15000); expire = callback; return 1;
  });
  t.mock.method(global, 'clearTimeout', () => {});
  const f = fixture(() => new Promise(() => {}));
  const pending = f.create().resolve(initial, 'app-id');
  expire();
  await assert.rejects(pending, e => e.code === 'LINE_ENTRY_RESOLVE_FAILED');
  assert.equal(f.clients[0].destroyed, 1);
});

test('closing Binding cancels pending entry and does not publish a home URL', async () => {
  const f = fixture(() => new Promise(() => {}));
  const { MiniAppSession } = f.load('main/ets/core/Runtime');
  const { LineVendor } = f.load('main/ets/vendors/line/LineVendor');
  const vendor = new LineVendor();
  const { LineAdapter } = f.load('main/ets/vendors/line/LineAdapter');
  const session = new MiniAppSession('closing', { info: { appId: 'app-id', vendor: 'line', url: initial },
    vendor, adapter: new LineAdapter({ mode: 'web' }), swipeBackController: { dispose() {} } }, {});
  const binding = session.getBinding();
  const pending = binding.prepareInitialLoad();
  session.close();
  await assert.rejects(pending, e => e.code === 'LINE_SESSION_CLOSED');
  assert.equal(binding.getResolvedEntryUrl(), undefined);
  assert.equal(f.clients[0].destroyed, 1);
});

test('Binding resolves only unauthenticated main launch and home uses resolved URL', async () => {
  const f = fixture();
  const { MiniAppSession } = f.load('main/ets/core/Runtime');
  const { LineVendor } = f.load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = f.load('main/ets/vendors/line/LineAdapter');
  const vendor = new LineVendor(); const adapter = new LineAdapter({ mode: 'web' });
  const session = new MiniAppSession('entry', { info: { appId: 'app-id', vendor: 'line', url: initial },
    vendor, adapter, swipeBackController: { dispose() {} } }, {});
  const binding = session.getBinding();
  const navigation = adapter.createNavigationController(); const loaded = [];
  navigation.attach({ session, controller: { loadUrl: (...args) => loaded.push(args) },
    goHome() { throw new Error('must not return to guide'); } });
  navigation.goHome();
  assert.equal(loaded.length, 0); // Preparation has not finished.
  assert.equal((await binding.prepareInitialLoad()).url, endpoint);
  navigation.goHome();
  assert.equal(loaded[0][0], endpoint);
  assert.equal(session.initialUrl, initial);
  session.close(); navigation.goHome();
  assert.equal(loaded.length, 1);
});

test('ordinary business entry retains history-based home behavior', async () => {
  const f = fixture();
  const { MiniAppSession } = f.load('main/ets/core/Runtime');
  const { LineVendor } = f.load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = f.load('main/ets/vendors/line/LineAdapter');
  const vendor = new LineVendor(); const adapter = new LineAdapter({ mode: 'web' });
  const session = new MiniAppSession('ordinary', { info: { appId: 'app-id', vendor: 'line', url: endpoint },
    vendor, adapter, swipeBackController: { dispose() {} } }, {});
  await session.getBinding().prepareInitialLoad();
  let homes = 0;
  const navigation = adapter.createNavigationController();
  navigation.attach({ session, controller: { loadUrl() { throw new Error('must use history'); } },
    goHome() { homes++; } });
  navigation.goHome();
  assert.equal(homes, 1);
  assert.equal(f.clients.length, 0);
  session.close();
});

test('late navigation resolution is discarded after document changes', async () => {
  let finish;
  const f = fixture(() => new Promise(resolve => { finish = resolve; }));
  const { MiniAppSession } = f.load('main/ets/core/Runtime');
  const { LineVendor } = f.load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = f.load('main/ets/vendors/line/LineAdapter');
  const session = new MiniAppSession('navigation', { info: { appId: 'app-id', vendor: 'line', url: endpoint },
    vendor: new LineVendor(), adapter: new LineAdapter({ mode: 'web' }),
    swipeBackController: { dispose() {} } }, {});
  session.beginDocument(endpoint);
  const binding = session.getBinding();
  const pending = binding.prepareNavigation(initial);
  session.beginDocument('https://app.example/other');
  finish({ responseCode: 200, result: html() });
  await assert.rejects(pending, e => e.code === 'DOCUMENT_CHANGED');
  assert.equal(binding.getResolvedEntryUrl(), undefined);
  session.close();
});

test('WEB child launch keeps its prepared URL without requesting the guide', async () => {
  const f = fixture();
  const { MiniAppSession } = f.load('main/ets/core/Runtime');
  const { LineVendor } = f.load('main/ets/vendors/line/LineVendor');
  const { LineAdapter } = f.load('main/ets/vendors/line/LineAdapter');
  const launch = { liffId: 'app-id', result: {}, webLogin: true };
  const session = new MiniAppSession('child', { info: { appId: 'app-id', vendor: 'line', url: initial },
    vendor: new LineVendor(launch), adapter: new LineAdapter({ mode: 'web' }),
    swipeBackController: { dispose() {} } }, {});
  assert.equal((await session.getBinding().prepareInitialLoad()).url, initial);
  assert.equal(f.clients.length, 0);
  session.close();
});
