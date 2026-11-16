const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const tick = () => new Promise(resolve => setImmediate(resolve));
global.DialogAlignment = { Center: 0 };

function fixture({ pendingWindow = false, pendingOpen = false } = {}) {
  let finishWindow, finishOpen, content, closed = 0, disposed = 0;
  const prompt = {
    async openCustomDialog() { if (pendingOpen) await new Promise(resolve => { finishOpen = resolve; }); },
    async closeCustomDialog() { closed++; }
  };
  const hostWindow = { getUIContext: () => ({ getPromptAction: () => prompt }) };
  class Content {
    constructor(_context, _builder, params) { this.params = params; content = this; }
    dispose() { disposed++; }
  }
  const load = createLoader(undefined, undefined, {
    getLastWindow: () => pendingWindow ? new Promise(resolve => { finishWindow = resolve; }) : Promise.resolve(hostWindow)
  }, undefined, undefined, undefined, { '@kit.ArkUI': { ComponentContent: Content } });
  const { LineScanResultDialogHost } = load('main/ets/vendors/line/scan/LineScanResultDialogHost');
  const { LineScanResultAction: A } = load('main/ets/vendors/line/scan/LineScanResultTypes');
  const host = new LineScanResultDialogHost({});
  return { host, A, get content() { return content; }, get closed() { return closed; },
    get disposed() { return disposed; }, finishWindow: () => finishWindow(hostWindow), finishOpen: () => finishOpen() };
}

test('result action is delivered after dialog release and duplicate actions are ignored', async () => {
  const f = fixture(); const result = f.host.show('text', false, () => true); await tick();
  f.content.params.complete(f.A.COPY); f.content.params.complete(f.A.OPEN);
  assert.equal(await result, f.A.COPY);
  assert.equal(f.closed, 1); assert.equal(f.disposed, 1);
  assert.equal(f.content.params.value, '');
});

test('cancelling before window lookup completes cannot mount a late result dialog', async () => {
  const f = fixture({ pendingWindow: true }); const result = f.host.show('private', false, () => true);
  f.host.dismiss(); f.finishWindow();
  assert.equal(await result, f.A.CLOSE); assert.equal(f.content, undefined);
});

test('cancelling during attachment waits for open before close and clears result content', async () => {
  const f = fixture({ pendingOpen: true }); const result = f.host.show('private', false, () => true); await tick();
  f.host.dismiss(); assert.equal(f.closed, 0); assert.equal(f.disposed, 0);
  f.finishOpen(); assert.equal(await result, f.A.CLOSE);
  assert.equal(f.closed, 1); assert.equal(f.disposed, 1); assert.equal(f.content.params.value, '');
});

test('source becoming inactive during window lookup cannot mount the result dialog', async () => {
  const f = fixture({ pendingWindow: true }); let current = true;
  const result = f.host.show('private', false, () => current);
  current = false; f.finishWindow();
  await tick(); assert.equal(f.content, undefined);
  assert.equal(await result, f.A.CLOSE);
});
