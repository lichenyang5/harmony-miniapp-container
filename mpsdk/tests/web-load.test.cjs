const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');

test('WebView load checks the originating document before loading the same endpoint', async () => {
  const load = createLoader(); const { MiniAppSession } = load('main/ets/core/Runtime');
  const calls = [];
  const session = new MiniAppSession('resume', {
    info: { appId: 'one', vendor: 'test', url: 'https://one.example' }, adapter: { vendorId: 'test' },
    vendor: { vendorId: 'test', createBinding: () => ({ injections: [], scripts: [], onDocumentChanged() {}, dispose() {} }) },
    swipeBackController: { dispose() {} }
  }, {});
  session.attach({ evaluate: async () => '', pauseAllMedia() {}, load: (...args) => calls.push(args) });
  session.lifecycle.setHostForeground(true);
  session.beginDocument('https://one.example');
  const script = { script: 'window.test=1', scriptRules: ['*'] };
  await session.load({ url: 'https://shop.example/callback' }, 1, [script]);
  assert.deepEqual(calls.map(args => args.slice(0, 2)), [[{ url: 'https://shop.example/callback' }, [script]]]);
  session.beginDocument('https://one.example/next');
  await assert.rejects(session.load({ url: 'https://shop.example/stale' }, 1, []));
  session.close();
  await assert.rejects(session.load({ url: 'https://shop.example/closed' }, 2, []));
  assert.equal(calls.length, 1);
});

test('ArkWeb loading waits for declarative document scripts before loadUrl without account headers', async () => {
  const { ArkWebEndpoint } = createLoader()('main/ets/web/ArkWebEndpoint');
  const calls = [];
  let installed;
  const endpoint = new ArkWebEndpoint({ loadUrl: (...args) => calls.push(['load', ...args]) },
    scripts => { calls.push(['scripts', scripts]); return new Promise(resolve => { installed = resolve; }); });
  const pending = endpoint.load({ url: 'https://shop.example/callback' }, []);
  assert.deepEqual(calls, [['scripts', []]]);
  installed(); await pending;
  assert.deepEqual(calls, [['scripts', []], ['load', 'https://shop.example/callback']]);
});

test('load cannot publish an old document after asynchronous script installation', async () => {
  const { ArkWebEndpoint } = createLoader()('main/ets/web/ArkWebEndpoint');
  let installed, current = true; const loads = [];
  const endpoint = new ArkWebEndpoint({ loadUrl: url => loads.push(url) },
    () => new Promise(resolve => { installed = resolve; }));
  const pending = endpoint.load({ url: 'https://shop.example/callback' }, [], () => current);
  current = false; installed();
  await assert.rejects(pending, error => error.code === 'DOCUMENT_CHANGED');
  assert.deepEqual(loads, []);
});
