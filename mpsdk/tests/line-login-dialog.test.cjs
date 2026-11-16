const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
global.DialogAlignment = { Center: 0 };
global.DismissReason = { PRESS_BACK: 0, TOUCH_OUTSIDE: 1 };
const tick = () => new Promise(resolve => setImmediate(resolve));

test('system back first delegates keyboard dismissal and cancels only after keyboard is hidden', async () => {
 let params; let options; let cancelled = 0; let dismissed = 0; let keyboardVisible = true;
 const prompt = { openCustomDialog: async (content, value) => { params = content.params; options = value; },
   closeCustomDialog: async () => {} };
 class Content { constructor(_ui, _builder, value) { this.params = value; } dispose() {} }
 const load = createLoader(undefined, undefined, { getLastWindow: async () => ({
   getUIContext: () => ({ getPromptAction: () => prompt }) }) }, undefined, undefined, undefined,
   { '@kit.ArkUI': { ComponentContent: Content } });
 const { LineLoginDialogHost } = load('main/ets/vendors/line/auth/ui/LineLoginDialogHost');
 const host = new LineLoginDialogHost({});
 await host.show({ cancel() { cancelled++; } });
 params.model.dismissKeyboard = () => keyboardVisible;
 const action = { reason: DismissReason.PRESS_BACK, dismiss() { dismissed++; } };
 options.onWillDismiss(action); assert.equal(cancelled, 0); assert.equal(dismissed, 0);
 keyboardVisible = false;
 options.onWillDismiss(action); assert.equal(cancelled, 1);
 await host.hide();
 options.onWillDismiss(action); assert.equal(cancelled, 1); assert.equal(dismissed, 1);
});
test('late open closes its own content and preserves early state', async () => {
 let finish; let params; let options; let disposed = 0; let closed = 0; let cancelled = 0;
 const prompt = { openCustomDialog(c, o) { params = c.params; options = o; return new Promise(r => { finish = r; }); }, closeCustomDialog: async () => { closed++; } };
 class Content { constructor(_ui, _builder, p) { this.params = p; } dispose() { disposed++; } }
 const load = createLoader(undefined, undefined, { getLastWindow: async () => ({ getUIContext: () => ({ getPromptAction: () => prompt }) }) }, undefined, undefined, undefined, { '@kit.ArkUI': { ComponentContent: Content } });
 const { LineLoginDialogHost } = load('main/ets/vendors/line/auth/ui/LineLoginDialogHost');
 const host = new LineLoginDialogHost({});
 host.update({ phase: 'qr', method: 'qr', qrUrl: 'value' });
 const shown = host.show({ cancel() { cancelled++; } }); await tick();
 assert.equal(options.keyboardAvoidMode, KeyboardAvoidMode.NONE);
 assert.equal(params.model.state.qrUrl, 'value');
 await host.hide(); assert.equal(disposed, 0); finish(); await shown;
 assert.equal(closed, 1); assert.equal(disposed, 1); options.onDidDisappear(); assert.equal(cancelled, 0);
});

test('system disappearance cancels once while programmatic hide never cancels', async () => {
 let options; let closed = 0; let disposed = 0; let cancelled = 0;
 const prompt = { openCustomDialog: async (_c, o) => { options = o; }, closeCustomDialog: async () => { closed++; } };
 class Content { dispose() { disposed++; } }
 const load = createLoader(undefined, undefined, { getLastWindow: async () => ({ getUIContext: () => ({ getPromptAction: () => prompt }) }) }, undefined, undefined, undefined, { '@kit.ArkUI': { ComponentContent: Content } });
 const { LineLoginDialogHost } = load('main/ets/vendors/line/auth/ui/LineLoginDialogHost');
 const host = new LineLoginDialogHost({}); const actions = { cancel() { cancelled++; } };
 await host.show(actions); options.onDidDisappear(); await tick(); options.onDidDisappear();
 assert.equal(cancelled, 1); assert.equal(disposed, 1); assert.equal(closed, 1);
 await host.show(actions); await host.hide(); options.onDidDisappear();
 assert.equal(cancelled, 1); assert.equal(disposed, 2); assert.equal(closed, 2);
});


test('hide reports a close failure and still disposes its content', async () => {
 let disposed = 0; const cause = new Error('platform close failure');
 const prompt = { openCustomDialog: async () => {}, closeCustomDialog: async () => { throw cause; } };
 class Content { dispose() { disposed++; } }
 const load = createLoader(undefined, undefined, { getLastWindow: async () => ({ getUIContext: () => ({ getPromptAction: () => prompt }) }) }, undefined, undefined, undefined, { '@kit.ArkUI': { ComponentContent: Content } });
 const { LineLoginDialogHost } = load('main/ets/vendors/line/auth/ui/LineLoginDialogHost');
 const host = new LineLoginDialogHost({});
 await host.show({ cancel() {} });
 await assert.rejects(host.hide(), error => error.code === 'LINE_LOGIN_UI_FAILED' && error.originalCause === cause);
 assert.equal(disposed, 1);
});
