const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { createLoader } = require('./sdk-loader.cjs');
const read = file => fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
const flush = () => new Promise(resolve => setImmediate(resolve));
global.DialogAlignment = { Bottom: 2 };

test('the public container owns only the parent and LINE owns the dialog', () => {
  const container = read('src/main/ets/web/MiniAppContainer.ets');
  assert.equal(read('Index.ets').includes('LineContainer'), false);
  assert.equal(container.includes('VendorViewRegistry'), false);
  assert.equal(container.includes('LineBinding'), false);
  assert.equal(container.includes('LineDialog'), false);
  assert.ok(read('../entry/src/main/ets/pages/LinePage.ets').includes('MiniAppContainer'));
});

function fixture(pendingOpen = false) {
  const contents = [];
  const closed = [];
  let options;
  let resolveOpen;
  let closeRequests = 0;
  const failures = [];
  class Content {
    constructor(_ui, _builder, params) { this.params = params; this.disposed = 0; contents.push(this); }
    dispose() { this.disposed++; }
  }
  const prompt = {
    openCustomDialog: async (_content, opts) => {
      options = opts;
      if (pendingOpen) await new Promise(resolve => { resolveOpen = resolve; });
    },
    closeCustomDialog: async content => { closed.push(content); options.onDidDisappear(); },
    showToast() {}
  };
  const ui = { getPromptAction: () => prompt };
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined, {
    '@kit.ArkUI': { ComponentContent: Content, window: { getLastWindow: async () => ({ getUIContext: () => ui }) } }
  });
  const { LineDialogHost } = load('main/ets/vendors/line/LineDialogHost');
  const host = new LineDialogHost({}, {
    requestClose: () => { closeRequests++; },
    onFailure: error => failures.push(error),
    onError() {}
  });
  const session = { getBinding: () => ({ getInitialHeaders: () => [] }) };
  return { host, session, contents, closed, failures, get options() { return options; },
    get closeRequests() { return closeRequests; }, finishOpen: () => resolveOpen() };
}

test('dialog back delegates closing to the window controller and releases content when hidden', async () => {
  const f = fixture(); await f.host.show(f.session);
  assert.equal(f.options.autoCancel, false);
  assert.equal(f.options.isModal, true);
  let dismissed = false;
  f.options.onWillDismiss({ dismiss() { dismissed = true; } });
  assert.equal(f.closeRequests, 1);
  assert.equal(dismissed, false);
  assert.equal(f.closed.length, 0);
  f.host.hide(); await flush();
  assert.equal(f.closed.length, 1);
  assert.equal(f.contents[0].disposed, 1);
  assert.equal(f.failures.length, 0);
});

test('dialog accepts explicit initial headers without inspecting a concrete binding', async () => {
  const f = fixture();
  const session = { getBinding() { throw new Error('dialog must not inspect bindings'); } };
  const headers = [{ headerKey: 'X-LINE-LIFF-TOKEN', headerValue: 'child-token' }];
  await f.host.show(session, headers);
  assert.deepEqual(f.contents[0].params.headers, headers);
  f.host.dispose(); await flush();
});

test('dialog receives a separate presentation snapshot in a bottom-aligned content host', async () => {
  const f = fixture();
  const presentation = { presentationType: 3, closeButtonPosition: 2, closeButtonLabel: 'Done', hideCloseButton: false };
  await f.host.show(f.session, [], presentation);
  assert.deepEqual(f.contents[0].params.presentation, presentation);
  assert.ok(f.contents[0].params.hostWindow);
  presentation.presentationType = 1;
  assert.equal(f.contents[0].params.presentation.presentationType, 3);
  assert.equal(f.options.alignment, DialogAlignment.Bottom);
  f.host.dispose(); await flush();
});

test('a dialog that finishes opening after disposal is immediately closed and released', async () => {
  const f = fixture(true);
  const opening = f.host.show(f.session); await flush();
  f.host.dispose();
  f.finishOpen(); await opening; await flush();
  assert.equal(f.closed.length, 1);
  assert.equal(f.contents[0].disposed, 1);
  f.host.dispose();
  assert.equal(f.contents[0].disposed, 1);
});

test('unexpected dialog dismissal reports failure; ordinary hide does not report twice', async () => {
  const f = fixture(); await f.host.show(f.session);
  f.options.onDidDisappear(); await flush();
  assert.equal(f.failures.length, 1);
  assert.equal(f.failures[0].code, 'LINE_SUBWINDOW_DISMISSED');
  f.host.hide(); await flush();
  assert.equal(f.contents[0].disposed, 1);
});

test('a queued close callback from the old dialog cannot close the new child', async () => {
  const f = fixture(); await f.host.show(f.session);
  const oldClose = f.contents[0].params.requestClose;
  f.host.hide();
  await f.host.show(f.session);
  oldClose();
  assert.equal(f.closeRequests, 0);
  f.contents[1].params.requestClose();
  assert.equal(f.closeRequests, 1);
  f.host.dispose(); await flush();
  f.contents[1].params.requestClose();
  assert.equal(f.closeRequests, 1);
});
