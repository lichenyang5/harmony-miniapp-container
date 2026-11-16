const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const source = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/model/LineBridgeDiagnostics.ets'), 'utf8');
const exported = {};
new Function('exports', ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText)(exported);

async function fixture(contextId = '123-abc', initiallyMissing = false) {
  const nodes = [];
  let calls = 0;
  const window = { liff: { ready: Promise.resolve(), getContext: () => ({ liffId: contextId }),
    isInClient: () => false, scanCodeV2: async () => { calls++; return { value: 'real-result' }; } } };
  let hide;
  window.addEventListener = (_event, callback) => { hide = callback; };
  window.top = window;
  const liff = window.liff;
  if (initiallyMissing) window.liff = undefined;
  const timers = [];
  const document = { getElementById: () => undefined, body: { appendChild() {} },
    createElement: tag => { const node = { tag, style: {}, appendChild() {}, remove() {} };
      nodes.push(node); return node; } };
  vm.runInNewContext(exported.lineBridgeDiagnostics('123-abc'), { window, document,
    setTimeout: callback => { timers.push(callback); return timers.length; }, clearTimeout() {} });
  await new Promise(resolve => setImmediate(resolve));
  return { window, nodes, calls: () => calls, hide: () => hide(),
    async restore() { window.liff = liff; timers.shift()?.();
      await new Promise(resolve => setImmediate(resolve)); } };
}

test('debug panel invokes real LIFF scanning only on a user click and preserves client state', async () => {
  const f = await fixture();
  assert.equal(f.calls(), 0);
  const button = f.nodes.find(node => node.textContent === '原生扫码 / Scan');
  assert.ok(button);
  await button.onclick();
  assert.equal(f.calls(), 1);
  assert.equal(f.window.liff.isInClient(), false);
  assert.ok(f.nodes.some(node => node.textContent?.includes('real-result')));
  assert.equal(button.disabled, false);
});

test('debug panel is absent for another LIFF identity', async () => {
  const f = await fixture('other-id');
  assert.equal(f.nodes.length, 0);
  assert.equal(f.calls(), 0);
});

test('debug panel waits for late LIFF publication without changing its object', async () => {
  const f = await fixture('123-abc', true);
  assert.equal(f.nodes.length, 0);
  await f.restore();
  assert.ok(f.nodes.some(node => node.textContent === '原生扫码 / Scan'));
  assert.equal(f.calls(), 0);
});

test('page exit prevents late LIFF publication from mounting a panel', async () => {
  const f = await fixture('123-abc', true);
  f.hide();
  await f.restore();
  assert.equal(f.nodes.length, 0);
});
