const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');

const insets = { top: 24, right: 8, bottom: 16, left: 12 };

test('the close entry uses the APK overlay, icon and label dimensions', () => {
  const layout = createLoader()('main/ets/vendors/line/LineDialogLayout');
  assert.equal(layout.LINE_DIALOG_CLOSE_HEIGHT, 50);
  assert.equal(layout.LINE_DIALOG_CLOSE_ICON_SIZE, 24);
  assert.equal(layout.LINE_DIALOG_CLOSE_ICON_MARGIN, 12);
  assert.equal(layout.LINE_DIALOG_CLOSE_LABEL_MARGIN, 16);
  assert.equal(layout.LINE_DIALOG_CLOSE_FONT_SIZE, '17fp');
});

test('portrait child panels use the available viewport and the three presentation ratios', () => {
  const { computeLineDialogLayout } = createLoader()('main/ets/vendors/line/LineDialogLayout');
  assert.deepEqual(computeLineDialogLayout(400, 840, insets, 3),
    { width: 380, height: 400, topCornerRadius: 12 });
  assert.deepEqual(computeLineDialogLayout(400, 840, insets, 2),
    { width: 380, height: 640, topCornerRadius: 12 });
  assert.deepEqual(computeLineDialogLayout(400, 840, insets, 1),
    { width: 380, height: 800, topCornerRadius: 0 });
});

test('missing and unknown presentation values fall back to a full panel', () => {
  const { computeLineDialogLayout } = createLoader()('main/ets/vendors/line/LineDialogLayout');
  for (const presentation of [undefined, 0, 4, -1, NaN]) {
    assert.deepEqual(computeLineDialogLayout(400, 840, insets, presentation),
      { width: 380, height: 800, topCornerRadius: 0 });
  }
});

test('rotation recomputes full available height while partial modes retain their corner treatment', () => {
  const { computeLineDialogLayout } = createLoader()('main/ets/vendors/line/LineDialogLayout');
  for (const presentation of [2, 3]) {
    const portrait = computeLineDialogLayout(400, 840, insets, presentation);
    const landscape = computeLineDialogLayout(840, 400, insets, presentation);
    assert.ok(portrait.height < 800);
    assert.deepEqual(landscape, { width: 820, height: 360, topCornerRadius: 12 });
  }
  assert.equal(computeLineDialogLayout(840, 400, insets, 1).topCornerRadius, 0);
});

test('an unavailable or fully occluded viewport never creates a negative panel', () => {
  const { computeLineDialogLayout } = createLoader()('main/ets/vendors/line/LineDialogLayout');
  assert.deepEqual(computeLineDialogLayout(0, 0, insets, 3),
    { width: 0, height: 0, topCornerRadius: 12 });
});

// Execute the real view lifecycle, omitting only ArkUI's declarative build methods.
function viewFixture(failOn, failOff) {
  const source = fs.readFileSync(path.join(__dirname,
    '../src/main/ets/vendors/line/LineDialogView.ets'), 'utf8');
  const parsed = ts.createSourceFile('LineDialogView.ts',
    source.replace('struct LineDialogView', 'class LineDialogView'), ts.ScriptTarget.ES2021, true);
  const declaration = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'LineDialogView');
  assert.ok(declaration);
  const methodNames = new Set(['aboutToAppear', 'aboutToDisappear', 'updateLayout', 'requestClose']);
  const members = declaration.members.filter(node => ts.isPropertyDeclaration(node) ||
    (ts.isMethodDeclaration(node) && ts.isIdentifier(node.name) && methodNames.has(node.name.text)))
    .map(node => ts.isPropertyDeclaration(node) ? ts.factory.updatePropertyDeclaration(node,
      node.modifiers?.filter(modifier => !ts.isDecorator(modifier)), node.name, node.questionToken,
      node.type, node.initializer) : node);
  const lifecycle = ts.createPrinter().printNode(ts.EmitHint.Unspecified,
    ts.factory.createClassDeclaration(undefined, 'LineDialogView', undefined, undefined, members), parsed);
  const { computeLineDialogLayout } = createLoader()('main/ets/vendors/line/LineDialogLayout');
  const javascript = ts.transpileModule(lifecycle, {
    compilerOptions: { target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const View = new Function('computeLineDialogLayout', 'readLineDialogInsets',
    `${javascript}; return LineDialogView;`)(computeLineDialogLayout, () => ({ ...insets }));
  const listeners = new Map();
  const removals = [];
  let rect = { width: 400, height: 840 };
  const hostWindow = {
    getWindowProperties: () => ({ windowRect: rect }),
    on(type, callback) {
      if (type === failOn) throw new Error('unavailable listener');
      listeners.set(type, callback);
    },
    off(type, callback) {
      removals.push(type);
      assert.equal(listeners.get(type), callback);
      if (type === failOff) throw new Error('destroyed window');
      listeners.delete(type);
    }
  };
  const view = new View();
  view.params = { hostWindow, presentation: { presentationType: 3 } };
  view.getUIContext = () => ({ px2vp: value => value });
  return { view, listeners, removals, rotate: () => { rect = { width: 840, height: 400 }; } };
}

test('the view updates after rotation and ignores late callbacks after independently releasing listeners', () => {
  const f = viewFixture(undefined, 'windowSizeChange');
  f.view.aboutToAppear();
  assert.equal(f.view.layout.height, 400);
  const lateSize = f.listeners.get('windowSizeChange');
  const lateInsets = f.listeners.get('avoidAreaChange');
  f.rotate(); lateSize({ width: 840, height: 400 });
  assert.equal(f.view.layout.height, 360);
  f.view.aboutToDisappear();
  assert.deepEqual(f.removals, ['windowSizeChange', 'avoidAreaChange']);
  f.view.layout = { width: 1, height: 2, topCornerRadius: 3 };
  lateSize({}); lateInsets({});
  assert.deepEqual(f.view.layout, { width: 1, height: 2, topCornerRadius: 3 });
  f.view.aboutToDisappear();
  assert.equal(f.removals.length, 2);
});

test('one failed listener registration does not prevent the other listener from updating or releasing', () => {
  for (const unavailable of ['windowSizeChange', 'avoidAreaChange']) {
    const f = viewFixture(unavailable);
    f.view.aboutToAppear();
    assert.equal(f.listeners.size, 1);
    f.rotate();
    [...f.listeners.values()][0]({});
    assert.equal(f.view.layout.height, 360);
    f.view.aboutToDisappear();
    assert.equal(f.listeners.size, 0);
    assert.equal(f.removals.length, 1);
  }
});

test('backdrop and close entry request native close only while the dialog is active', () => {
  const f = viewFixture();
  let closes = 0;
  f.view.params.requestClose = () => { closes++; };
  f.view.aboutToAppear();
  assert.equal(typeof f.view.requestClose, 'function');
  f.view.requestClose();
  assert.equal(closes, 1);
  f.view.aboutToDisappear();
  f.view.requestClose();
  assert.equal(closes, 1);
});
