const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');

function fixture() {
  const source = fs.readFileSync(path.join(__dirname,
    '../src/main/ets/vendors/line/auth/ui/LineLoginView.ets'), 'utf8');
  const parsed = ts.createSourceFile('LineLoginView.ts', source.replace('struct LineLoginView', 'class LineLoginView'),
    ts.ScriptTarget.ES2021, true);
  const declarations = parsed.statements.filter(ts.isClassDeclaration);
  const modelClass = declarations.find(node => node.name?.text === 'LineLoginViewModel');
  assert.ok(modelClass);
  const members = modelClass.members.map(node => ts.isPropertyDeclaration(node) ?
    ts.factory.updatePropertyDeclaration(node, node.modifiers?.filter(modifier => !ts.isDecorator(modifier)),
      node.name, node.questionToken, node.type, node.initializer) : node);
  const modelSource = ts.createPrinter().printNode(ts.EmitHint.Unspecified,
    ts.factory.createClassDeclaration(undefined, 'LineLoginViewModel', undefined, undefined, members), parsed);
  const modelJs = ts.transpileModule(modelSource, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
  const Model = new Function(`${modelJs};return LineLoginViewModel;`)();
  const viewClass = declarations.find(node => node.name?.text === 'LineLoginView');
  const emailActions = viewClass.members.find(node => ts.isMethodDeclaration(node) && node.name?.text === 'emailActions');
  assert.ok(emailActions, 'the email action builder must be present');
  let submit;
  function visit(node) {
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) && node.expression.name.text === 'onClick') {
      const action = node.arguments[0];
      let invokesLogin = false;
      function findLogin(child) {
        if (ts.isCallExpression(child) && ts.isPropertyAccessExpression(child.expression) &&
          child.expression.name.text === 'submitEmail') invokesLogin = true;
        ts.forEachChild(child, findLogin);
      }
      if (action) findLogin(action);
      if (invokesLogin) submit = action;
    }
    ts.forEachChild(node, visit);
  }
  visit(emailActions); assert.ok(submit, 'email button must invoke login');
  const model = new Model(), calls = [];
  const view = { params: { model, actions: { submitEmail(email, password) { calls.push({ email, password }); } } } };
  const js = ts.transpileModule(`const submit = ${submit.getText(parsed)};`,
    { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
  return { model, calls, submit: new Function(`${js};return submit;`).call(view) };
}

test('email submission and failed login preserve both inputs for an explicit retry', () => {
  const f = fixture(); f.model.email = 'a@example.test'; f.model.password = 'test password';
  f.submit();
  assert.deepEqual(f.calls, [{ email: 'a@example.test', password: 'test password' }]);
  assert.equal(f.model.email, 'a@example.test'); assert.equal(f.model.password, 'test password');
  f.model.update({ phase: 'failed', method: 'email', errorCode: 'LINE_EMAIL_SERVICE_ERROR_35' });
  f.submit(); assert.deepEqual(f.calls[1], f.calls[0]);
});

test('explicit login-page cleanup still clears both inputs', () => {
  const f = fixture(); f.model.email = 'a@example.test'; f.model.password = 'test password';
  f.model.clearSecrets(); assert.equal(f.model.email, ''); assert.equal(f.model.password, '');
});
