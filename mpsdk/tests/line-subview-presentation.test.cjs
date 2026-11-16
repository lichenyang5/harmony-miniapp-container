const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
class PlatformURL extends URL { get params() { return this.searchParams; } }
const flush = () => new Promise(resolve => setImmediate(resolve));

function loader() {
  return createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } });
}
function result() {
  return { liffId: 'child', url: 'https://child.example/', accessToken: 'access',
    featureToken: 'feature', contextToken: 'context', presentationType: 3,
    closeButtonPosition: 2, closeButtonLabel: 'Finish', hideCloseButton: true };
}
const request = { liffId: 'child', msit: 'ticket', requestedUrl: 'https://liff.line.me/child' };

test('subview service preserves presentation through its independent host-result snapshot', async () => {
  const { LineSubViewService } = loader()('main/ets/vendors/line/liff/LineSubViewService');
  const response = result();
  const issued = await new LineSubViewService({ issueSubLiffView: async () => response }).issue(request);
  for (const key of ['presentationType', 'closeButtonPosition', 'closeButtonLabel', 'hideCloseButton']) {
    assert.equal(issued[key], response[key], key);
  }
  response.closeButtonLabel = 'mutated';
  assert.equal(issued.closeButtonLabel, 'Finish');
  for (const invalid of [{ presentationType: '3' }, { presentationType: 1.5 },
    { closeButtonPosition: null }, { closeButtonLabel: 42 }]) {
    await assert.rejects(new LineSubViewService({
      issueSubLiffView: async () => ({ ...result(), ...invalid })
    }).issue(request), error => error.code === 'LINE_SUBVIEW_INVALID');
  }
});

test('window controller explicitly forwards only presentation fields to the dialog host', async () => {
  const load = loader();
  const { LineWindowController } = load('main/ets/vendors/line/LineWindowController');
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const shown = [];
  const controller = new LineWindowController({ id: 'parent', info: {}, getDocumentId: () => 1 },
    new LineAdapter({ issueSubLiffView: async () => result() }),
    id => ({ id, close() {} }));
  controller.attach({ show: (_child, _headers, presentation) => shown.push(presentation),
    hide() {}, reportError: error => assert.fail(error.code) });
  controller.open('liff://subwindow?url=https%3A%2F%2Fliff.line.me%2Fchild&msit=ticket', 'verifier');
  await flush();
  assert.deepEqual(shown, [{ presentationType: 3, closeButtonPosition: 2,
    closeButtonLabel: 'Finish', hideCloseButton: true }]);
  controller.dispose();
});
