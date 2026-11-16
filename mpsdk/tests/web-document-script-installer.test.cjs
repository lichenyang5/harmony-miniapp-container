const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');

function fixture() {
  const frames = [], applied = [];
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkUI': { FrameCallback: class {} } });
  const { WebDocumentScriptInstaller } = load('main/ets/web/WebDocumentScriptInstaller');
  const installer = new WebDocumentScriptInstaller({ runScopedTask: task => task(),
    postFrameCallback: callback => frames.push(callback) }, scripts => applied.push(scripts));
  return { installer, frames, applied };
}

test('declarative scripts finish installing after the frame update, not at frame start', async () => {
  const f = fixture(); const scripts = [{ script: 'init()', scriptRules: ['*'] }];
  let ready = false;
  const pending = f.installer.install(scripts).then(() => { ready = true; });
  assert.deepEqual(f.applied, [scripts]);
  f.frames[0].onFrame(0); await Promise.resolve(); assert.equal(ready, false);
  f.frames[0].onIdle(1000000); await pending; assert.equal(ready, true);
});

test('replacing or disposing a pending installation rejects it and ignores late frame callbacks', async () => {
  const f = fixture();
  const first = f.installer.install([]); const rejected = assert.rejects(first, e => e.code === 'DOCUMENT_CHANGED');
  const second = f.installer.install([]); await rejected;
  const cancelled = assert.rejects(second, e => e.code === 'SESSION_CLOSED');
  f.installer.dispose(); await cancelled;
  f.frames.forEach(frame => frame.onIdle(1000000));
  await assert.rejects(f.installer.install([]), e => e.code === 'SESSION_CLOSED');
});
