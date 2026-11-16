const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const { createLoader } = require('./sdk-loader.cjs');

function fixture(listenerUnavailable = false) {
  const source = fs.readFileSync(path.join(__dirname,
    '../src/main/ets/vendors/line/auth/ui/LineLoginView.ets'), 'utf8');
  const parsed = ts.createSourceFile('LineLoginView.ts', source.replace('struct LineLoginView', 'class LineLoginView'),
    ts.ScriptTarget.ES2021, true);
  const declaration = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'LineLoginView');
  assert.ok(declaration);
  const methods = new Set(['aboutToAppear', 'aboutToDisappear', 'updateInsets', 'updateKeyboardHeight',
    'emailKeyboardInset', 'revealEmailField', 'updateEmailViewport', 'handleBack']);
  const members = declaration.members.filter(node => ts.isPropertyDeclaration(node) ||
    (ts.isMethodDeclaration(node) && methods.has(node.name?.text))).map(node => ts.isPropertyDeclaration(node) ?
    ts.factory.updatePropertyDeclaration(node, node.modifiers?.filter(modifier => !ts.isDecorator(modifier)),
      node.name, node.questionToken, node.type, node.initializer) : node);
  const text = ts.createPrinter().printNode(ts.EmitHint.Unspecified,
    ts.factory.createClassDeclaration(undefined, 'LineLoginView', undefined, undefined, members), parsed);
  const javascript = ts.transpileModule(text, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
  const AvoidAreaType = { TYPE_SYSTEM: 0, TYPE_CUTOUT: 1, TYPE_KEYBOARD: 3, TYPE_NAVIGATION_INDICATOR: 4 };
  const read = createLoader(undefined, undefined, { AvoidAreaType })('main/ets/vendors/line/LineDialogInsets').readLineDialogInsets;
  const constants = parsed.statements.filter(node => ts.isVariableStatement(node))
    .filter(node => node.declarationList.declarations.some(d => d.name.text === 'EMAIL_INPUT_HEIGHT' ||
      d.name.text === 'EMAIL_INPUT_GAP' || d.name.text === 'EMAIL_FORM_TOP' || d.name.text === 'LOGIN_BOTTOM_PADDING'));
  const declarations = constants.map(node => ts.createPrinter().printNode(ts.EmitHint.Unspecified, node, parsed)).join('\n');
  class Scroller {
    offset = 0;
    currentOffset() { return { xOffset: 0, yOffset: this.offset }; }
    scrollTo(options) { this.offset = options.yOffset; }
  }
  const View = new Function('readLineDialogInsets', 'window', 'Scroller',
    `${ts.transpileModule(declarations, {}).outputText}\n${javascript}; return LineLoginView;`)(read, { AvoidAreaType }, Scroller);
  const view = new View(); let removed = 0;
  const callbacks = new Map();
  const area = top => ({ topRect: { height: top }, rightRect: { width: 0 },
    bottomRect: { height: 0 }, leftRect: { width: 0 } });
  let statusHeight = 96;
  const hostWindow = {
    getWindowAvoidArea(type) {
      const result = area(type === 0 ? statusHeight : type === 1 ? 120 : 0);
      result.bottomRect.height = type === 4 ? 60 : type === 3 ? 900 : 0;
      return result;
    },
    on(event, listener) { if (listenerUnavailable) throw Error('unsupported'); callbacks.set(event, listener); },
    off(event, listener) {
      assert.equal(listener, callbacks.get(event));
      removed++;
    }
  };
  view.params = { hostWindow, model: { state: { method: 'email' } } };
  let focusCleared = 0;
  view.getUIContext = () => ({ px2vp: pixels => pixels / 3,
    getFocusController: () => ({ clearFocus() { focusCleared++; } }) });
  return { view, get removed() { return removed; }, get focusCleared() { return focusCleared; },
    change: height => { statusHeight = height; callbacks.get('avoidAreaChange')({}); },
    keyboard: height => callbacks.get('keyboardHeightChange')(height) };
}

test('login view reads real window insets, updates on changes and ignores late events after removal', () => {
  const f = fixture(); f.view.aboutToAppear();
  assert.deepEqual(f.view.insets, { top: 40, right: 0, bottom: 20, left: 0 });
  f.change(144); assert.equal(f.view.insets.top, 48);
  f.view.aboutToDisappear(); f.view.aboutToDisappear();
  assert.equal(f.removed, 2);
  f.change(180); assert.equal(f.view.insets.top, 48);
});

test('keyboard back clears focus without clearing credentials or guessing keyboard closure', () => {
  const f = fixture(); f.view.aboutToAppear();
  f.view.params.model.email = 'user@example.test';
  assert.equal(f.view.params.model.dismissKeyboard(), true);
  assert.equal(f.focusCleared, 1); assert.equal(f.view.keyboardHeight, 300);
  assert.equal(f.view.params.model.dismissKeyboard(), true);
  f.keyboard(0);
  assert.equal(f.view.params.model.dismissKeyboard(), false);
  assert.equal(f.view.params.model.email, 'user@example.test');
  const callback = f.view.params.model.dismissKeyboard;
  f.view.aboutToDisappear();
  assert.equal(f.view.params.model.dismissKeyboard, undefined);
  assert.equal(callback(), false);
});

test('back button keeps email inputs until the keyboard closes, then returns to QR', () => {
  const f = fixture(); f.view.aboutToAppear();
  let cleared = 0; let qr = 0; let cancelled = 0;
  f.view.params.model.clearSecrets = () => { cleared++; };
  f.view.params.actions = { showQr() { qr++; }, cancel() { cancelled++; } };
  f.view.handleBack(); assert.equal(cleared, 0); assert.equal(qr, 0);
  f.keyboard(0); f.view.handleBack();
  assert.equal(cleared, 1); assert.equal(qr, 1); assert.equal(cancelled, 0);
  f.view.params.model.state.method = 'qr'; f.view.handleBack();
  assert.equal(cancelled, 1);
});

test('email reserves only keyboard overlap not already covered by bottom padding and system inset', () => {
  const f = fixture(); f.view.aboutToAppear();
  assert.equal(f.view.emailKeyboardInset(), 256);
  f.keyboard(60); assert.equal(f.view.emailKeyboardInset(), 0);
  f.keyboard(900); f.view.params.model.state.method = 'qr';
  assert.equal(f.view.emailKeyboardInset(), 0);
  f.view.aboutToDisappear(); f.keyboard(0);
  assert.equal(f.view.keyboardHeight, 300);
});

test('email focus scrolls only enough to expose the input after viewport layout', () => {
  const f = fixture(); f.view.aboutToAppear();
  f.view.revealEmailField(1);
  assert.equal(f.view.emailScroller.offset, 0);
  f.view.updateEmailViewport(100);
  assert.equal(f.view.emailScroller.offset, 52);
  f.view.revealEmailField(0); assert.equal(f.view.emailScroller.offset, 40);
  f.view.updateEmailViewport(300); assert.equal(f.view.emailScroller.offset, 40);
  f.view.aboutToDisappear(); f.view.updateEmailViewport(10);
  assert.equal(f.view.emailScroller.offset, 40);
});

test('login view preserves initial insets when avoid area events are unavailable', () => {
  const f = fixture(true); f.view.aboutToAppear();
  assert.equal(f.view.insets.top, 40);
  f.view.aboutToDisappear(); assert.equal(f.removed, 0);
});
