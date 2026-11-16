const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject }; };

function fixture(child = false) {
  const { LineLiffDocument } = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } } })('main/ets/vendors/line/liff/LineLiffDocument');
  const loads = []; let current = 1, closed = false, foreground = true;
  const session = { appId: 'app', getAdapter: () => ({ getLiffId: () => 'app' }),
    getDocumentId: () => current, isClosed: () => closed,
    lifecycle: { isForeground: () => foreground }, load: async (...args) => loads.push(args) };
  return { document: new LineLiffDocument(session, child), loads, session, next: () => ++current,
    background: () => { foreground = false; }, close: () => { closed = true; } };
}

test('MST reads the issued identity through the session adapter without retaining a second ID', () => {
  const { LineLiffDocument } = createLoader()('main/ets/vendors/line/liff/LineLiffDocument');
  let state;
  const session = { appId: 'entry-alias', getAdapter: () => ({ getLiffId: () => state?.liffId }) };
  const document = new LineLiffDocument(session, false);
  assert.deepEqual(document.getScripts(), [], 'unknown identity must not produce an alias storage key');
  state = { liffId: 'issued-id', featureToken: 'feature' };
  assert.ok(document.getScripts()[0].script.includes('LIFF_STORE:issued-id:mstChallenge'));
  document.dispose();
  assert.deepEqual(document.getScripts(), []);
});

test('LIFF prepare produces the final URL without publishing MST or loading', async () => {
  const f = fixture(); const original = f.document.getMst();
  const navigation = f.document.prepare('https://shop.example/cb?state=a%2Bb#done', true, 1);
  assert.deepEqual(f.document.getMst(), original); assert.equal(f.loads.length, 0);
  assert.match(navigation.url, /state=a%2Bb/); assert.equal(new URL(navigation.url).hash, '#done');
  await navigation.load();
  const pair = f.document.getMst();
  assert.equal(new URL(navigation.url).searchParams.get('mst_challenge'), pair.challenge);
  assert.equal(f.loads.length, 1);
  assert.ok(f.loads[0][2].some(script => script.script.includes(pair.challenge)));
});

test('child starts without a separate MST and establishes its own pair only for approved OAuth', async () => {
  const f = fixture(true);
  assert.equal(f.document.getMst(), undefined); assert.deepEqual(f.document.getScripts(), []);
  const navigation = f.document.prepare('https://shop.example/cb?msit=old&state=a%2Bb', true, 1);
  assert.equal(f.document.getMst(), undefined);
  await navigation.load();
  assert.equal(new URL(navigation.url).searchParams.get('mst_verifier'), f.document.getMst().verifier);
  assert.equal(new URL(navigation.url).searchParams.get('msit'), '');
});

test('denial retains the URL, MST and derived scripts', async () => {
  const f = fixture(); const original = f.document.getMst();
  const target = 'https://shop.example/cb?error=access_denied#done';
  const navigation = f.document.prepare(target, false, 1); await navigation.load();
  assert.equal(navigation.url, target); assert.deepEqual(f.document.getMst(), original);
  assert.ok(f.document.getScripts()[0].script.includes(original.challenge));
});

test('old failed loads cannot overwrite a newer document MST, including after disposal', async () => {
  const f = fixture(), firstLoad = deferred(), secondLoad = deferred();
  let calls = 0; f.session.load = () => (++calls === 1 ? firstLoad.promise : secondLoad.promise);
  const first = f.document.prepare('https://shop.example/first', true, 1).load();
  const failed = assert.rejects(first);
  f.next();
  const second = f.document.prepare('https://shop.example/second', true, 2).load();
  const latest = f.document.getMst();
  firstLoad.reject(new Error('old failure')); await failed;
  assert.deepEqual(f.document.getMst(), latest);
  secondLoad.resolve(); await second;
  const pending = deferred(); f.session.load = () => pending.promise;
  const last = f.document.prepare('https://shop.example/last', true, 2).load();
  const rejected = assert.rejects(last);
  f.document.dispose(); pending.reject(new Error('disposed')); await rejected;
  assert.equal(f.document.getMst(), undefined); assert.deepEqual(f.document.getScripts(), []);
});

test('current failure rolls back its own MST and invalid documents never load', async () => {
  const f = fixture(); const original = f.document.getMst();
  f.session.load = async () => { throw new Error('load failed'); };
  await assert.rejects(f.document.prepare('https://shop.example/fail', true, 1).load());
  assert.deepEqual(f.document.getMst(), original);
  const stale = f.document.prepare('https://shop.example/stale', true, 1); f.next();
  await assert.rejects(stale.load(), error => error.code === 'DOCUMENT_CHANGED');
  f.document.dispose();
  assert.throws(() => f.document.prepare('https://shop.example/closed', true, 2));
});


test('LIFF document directly guards its Session generation, foreground, closure and own disposal', async () => {
  const f = fixture();
  assert.equal(f.document.getDocumentId(), 1); assert.equal(f.document.isCurrent(1), true);
  f.next(); assert.equal(f.document.getDocumentId(), 2); assert.equal(f.document.isCurrent(1), false);
  const original = f.document.getMst(); const prepared = f.document.prepare('https://shop.example/pending', true, 2);
  f.background(); assert.equal(f.document.isCurrent(2), false);
  await assert.rejects(prepared.load(), { code: 'DOCUMENT_CHANGED' });
  assert.deepEqual(f.document.getMst(), original); assert.equal(f.loads.length, 0);
  f.close(); assert.throws(() => f.document.prepare('https://shop.example/closed', true, 2), { code: 'SESSION_CLOSED' });
  const released = fixture(); released.document.dispose();
  assert.equal(released.document.isCurrent(1), false);
  assert.throws(() => released.document.prepare('https://shop.example/released', true, 1), { code: 'SESSION_CLOSED' });
});

test('a replaced approved installation cannot roll back the MST used by a later denied load', async () => {
  for (const child of [false, true]) {
    const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
      { '@kit.ArkTS': { url: { URL } }, '@kit.ArkUI': { FrameCallback: class {} } });
    const { MiniAppSession } = load('main/ets/core/Runtime');
    const { LineLiffDocument } = load('main/ets/vendors/line/liff/LineLiffDocument');
    const { ArkWebEndpoint } = load('main/ets/web/ArkWebEndpoint');
    const { WebDocumentScriptInstaller } = load('main/ets/web/WebDocumentScriptInstaller');
    const frames = [], applied = [], loaded = [];
    const installer = new WebDocumentScriptInstaller({ runScopedTask: fn => fn(),
      postFrameCallback: frame => frames.push(frame) }, scripts => applied.push(scripts));
    const endpoint = new ArkWebEndpoint({ loadUrl: url => loaded.push(url) }, scripts => installer.install(scripts));
    const session = new MiniAppSession('mst-denial-race', {
      info: { appId: 'app', vendor: 'line', url: 'https://shop.example/start' },
      adapter: { vendorId: 'line', getLiffId: () => 'app' },
      vendor: { vendorId: 'line', createBinding: () => ({ injections: [], scripts: [], onDocumentChanged() {}, dispose() {} }) },
      swipeBackController: { dispose() {} }
    }, {});
    session.attach(endpoint); session.lifecycle.setHostForeground(true); session.beginDocument('https://shop.example/start');
    const document = new LineLiffDocument(session, child);
    try {
      const first = document.prepare('https://shop.example/approved', true, session.getDocumentId()).load();
      const rejected = assert.rejects(first, { code: 'DOCUMENT_CHANGED' });
      const retained = document.getMst();
      session.beginDocument('https://shop.example/second');
      const deniedUrl = 'https://shop.example/denied?error=access_denied';
      const second = document.prepare(deniedUrl, false, session.getDocumentId()).load();
      const secondOutcome = second.then(() => undefined, error => error);
      await rejected;
      assert.deepEqual(document.getMst(), retained);
      frames[0].onIdle(1000000); assert.deepEqual(loaded, []);
      frames[1].onIdle(1000000); assert.equal(await secondOutcome, undefined);
      assert.deepEqual(loaded, [deniedUrl]);
      assert.deepEqual(document.getScripts(), applied[1]);
      assert.deepEqual(document.getMst(), retained);
    } finally {
      document.dispose(); installer.dispose(); session.close();
    }
  }
});
