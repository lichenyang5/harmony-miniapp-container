const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const tick = () => new Promise(setImmediate);
const base = 'main/ets/vendors/line/';
function presenter(context = {}) { return { context, shown:0, hidden:0, show:async function(session,back){this.session=session;this.back=back;this.shown++;}, update(){}, hide:async function(){this.hidden++;} }; }
function harness() {
  const load=createLoader();
  const { LineLoginCoordinator }=load(base+'auth/LineLoginCoordinator');
  let complete, reject, cancels=0, starts=0;
  const account={getVersion:()=>1,restoreSession:async()=>false,cancelLogin(){},startQrLogin(){return new Promise(()=>{});},startOwnedPhoneRegistration(state){starts++; const result=new Promise((a,b)=>{complete=a;reject=b;});return {result,getState:()=>({stage:'countrySelection'}),cancel(){cancels++;reject({code:'LINE_REGISTRATION_CANCELLED'});}};}};
  return {load,account,c:LineLoginCoordinator.forAccount(account),done:()=>complete(),get cancels(){return cancels;},get starts(){return starts;}};
}
test('built-in registration shares same ability and independent waiters',async()=>{
  const h=harness(),p=presenter(),a=h.c.requestRegistration(p),b=h.c.requestRegistration(presenter(p.context));
  await tick(); assert.equal(h.starts,1); assert.equal(p.shown,1);
  await assert.rejects(h.c.requestRegistration(presenter()).result,{code:'LINE_LOGIN_IN_PROGRESS'});
  a.cancel(); await assert.rejects(a.result); assert.equal(h.cancels,0); h.done();await b.result;assert.equal(p.hidden,1);
});
test('last registration waiter cancellation releases a late presentation',async()=>{
 const h=harness(),p=presenter();let shown;p.show=()=>new Promise(r=>shown=r);
 const a=h.c.requestRegistration(p);await tick();a.cancel();await assert.rejects(a.result);assert.equal(h.cancels,1);shown();await tick();assert.equal(p.hidden,1);
});
test('ordinary login owns idle email and pre-restore slot; external registration cannot seize it',async()=>{
 const h=harness();let restore;h.account.restoreSession=()=>new Promise(r=>restore=r);
 const p=presenter();p.show=async a=>{p.actions=a;};const a=h.c.request(p);
 const {LineAccountUiLease}=h.load(base+'auth/LineAccountUiLease');
 assert.throws(()=>LineAccountUiLease.assertRegistrationOwner(h.account),{code:'LINE_LOGIN_IN_PROGRESS'});
 await assert.rejects(h.c.requestRegistration(presenter(p.context)).result,{code:'LINE_LOGIN_IN_PROGRESS'});
 restore(false);await tick();p.actions.showEmail();assert.throws(()=>LineAccountUiLease.assertRegistrationOwner(h.account),{code:'LINE_LOGIN_IN_PROGRESS'});a.cancel();await assert.rejects(a.result);
});
test('switch identity precedes old cancellation; registration-only back never starts QR',async()=>{
 const h=harness(),p=presenter();let qr=0;h.account.startQrLogin=()=>{qr++;return new Promise(()=>{});};
 const a=h.c.requestRegistration(p);await tick();p.back();await assert.rejects(a.result);await tick();assert.equal(qr,0);
});

test('switch from ordinary login retains plain waiters; explicit registration never resolves from later QR',async()=>{
 const h=harness(),p=presenter(),r=presenter(p.context);let qrDone,qrStarts=0;
 p.show=async actions=>{p.actions=actions;};p.registrationPresenter=()=>r;
 h.account.startQrLogin=()=>{qrStarts++;return new Promise(resolve=>qrDone=resolve);};
 const a=h.c.request(p);await tick();p.actions.register();await tick();assert.equal(r.shown,1);
 const b=h.c.requestRegistration(presenter(p.context));let aDone=false;a.result.then(()=>aDone=true);
 r.back();await assert.rejects(b.result,{code:'LINE_REGISTRATION_CANCELLED'});await tick();
 assert.equal(aDone,false);assert.equal(qrStarts,2);qrDone('ready');await a.result;
});
test('interactive pending restore routes to continuation; reuseOnly rejects without UI; low-level lock never shows login',async()=>{
 for(const code of ['LINE_REGISTRATION_INCOMPLETE','LINE_LOGIN_IN_PROGRESS']){
  const h=harness(),p=presenter(),r=presenter(p.context);p.registrationPresenter=()=>r;
  const { MiniAppError }=h.load('main/ets/core/MiniAppError');h.account.restoreSession=async()=>{throw new MiniAppError(code,'safe');};
  const a=h.c.request(p);
  if(code==='LINE_LOGIN_IN_PROGRESS'){await assert.rejects(a.result,{code});assert.equal(p.shown,0);assert.equal(r.shown,0);}
  else {await tick();assert.equal(r.shown,1);h.done();await a.result;}
  const h2=harness();const {MiniAppError:Error2}=h2.load('main/ets/core/MiniAppError');h2.account.restoreSession=async()=>{throw new Error2(code,'safe');};
  await assert.rejects(h2.c.request(p,true).result,{code});
 }
});
test('real manager rejects low-level registration under idle UI lease',async()=>{
 const load=createLoader();const {LineAccountManager}=load(base+'auth/LineAccountManager');const {LineAccountUiLease}=load(base+'auth/LineAccountUiLease');
 const account=new LineAccountManager({cancel(){}},'model','system');const owner=LineAccountUiLease.acquire(account);
 assert.throws(()=>account.startPhoneRegistration(()=>{}),{code:'LINE_LOGIN_IN_PROGRESS'});
 LineAccountUiLease.release(account,owner);assert.throws(()=>account.startPhoneRegistration(()=>{}),{code:'LINE_CONNECTION_CONFIG_REQUIRED'});
});
test('registration WebView requires exact owned top document callbacks and verified routes',()=>{
 const load=createLoader({}, {}, undefined,undefined,undefined,undefined,{'@kit.ArkTS':{url:{URL}}});
 const {LineRegistrationWebProtocol:P,RegistrationWebDecision:D}=load(base+'registration/ui/LineRegistrationWebProtocol');
 const p=new P('https://challenge.line.me/start','challenge');p.begin('https://challenge.line.me/start');
 assert.equal(p.navigate('lineconnect://accepted',true,'https://challenge.line.me/start'),D.ACCEPTED);
 for(const callback of ['lineconnect://accepted/','lineconnect://accepted?x=1','lineconnect://allow','lineconnect://ACCEPTED'])assert.equal(p.navigate(callback,true,'https://challenge.line.me/start'),D.BLOCK);
 assert.equal(p.navigate('lineconnect://accepted',false,'https://challenge.line.me/start'),D.BLOCK);
 assert.equal(p.navigate('lineconnect://accepted',true,'https://challenge.line.me/other'),D.BLOCK);
 assert.equal(p.navigate('https://evil.test',true,'https://challenge.line.me/start'),D.BLOCK);
 assert.equal(p.navigate('https://captcha.provider.test/frame',false,'https://challenge.line.me/start'),D.LOAD);
 assert.equal(p.navigate('about:blank',false,'https://challenge.line.me/start'),D.LOAD);
 assert.equal(p.navigate('https://captcha.provider.test/frame',false,'https://other.test'),D.BLOCK);
 p.stop();assert.equal(p.navigate('lineconnect://accepted',true,'https://challenge.line.me/start'),D.BLOCK);
 assert.equal(P.pending('https://legy.line.test/S4',47,'en'),'https://legy.line.test/view/privacy/agreement/pending?agreement=47&language=en');
 for(const unknown of [53,66,55,56,68,76,92])assert.throws(()=>P.pending('https://legy.line.test',unknown,'en'));
 assert.equal(P.publicLocale('en-TW'),'zh-Hant');assert.equal(P.publicLocale('zh-Hans-CN'),'zh');assert.equal(P.publicLocale('en-ID'),'id');
});
test('actual form model clears password/code and does not dispatch after disposal',async()=>{
 const load=createLoader();const {LineRegistrationViewModel}=load(base+'registration/ui/LineRegistrationViewModel');
 const model=new LineRegistrationViewModel();model.password='secret';model.code='pin';model.update({stage:'creating'});assert.equal(model.password,'');assert.equal(model.code,'');
 model.password='secret';model.dispose();let calls=0;await model.perform(async()=>calls++);assert.equal(calls,0);assert.equal(model.password,'');
});

test('actual presentation port isolates challenge headers and public country decisions',async()=>{
 const load=createLoader({}, {}, undefined,undefined,undefined,undefined,{'@kit.ArkTS':{url:{URL}},'@kit.LocalizationKit':{i18n:{System:{getSystemLocale:()=> 'en-TW'}}}});
 const {LineRegistrationPresentationHost}=load(base+'registration/ui/LineRegistrationPresentationHost');
 const {RegistrationWebResult:R}=load(base+'registration/ui/LineRegistrationWebProtocol');
 const port=new LineRegistrationPresentationHost();const seen=[];let choice=R.ACCEPTED;port.host.show=async(...args)=>{seen.push(args);return choice;};
 assert.equal(await port.presentChallenge({}, {baseUrl:'https://challenge.line.me/',token:'raw-secret'}),true);
 assert.deepEqual(seen[0][2],[{headerKey:'Authorization',headerValue:'raw-secret'}]);
 const decision=await port.presentAgreement({},[],async()=>{throw Error('must not read account');},'GDPR');
 assert.equal(decision.policy,'GDPR');assert.ok(decision.timestampMs>0);assert.deepEqual(seen[1][2],[]);assert.match(seen[1][1],/lang=zh-Hant$/);
 choice=R.DECLINED;assert.ok((await port.presentAgreement({},[],async()=>{},'ICNA')).timestampMs<0);
 let credentials=0;await assert.rejects(port.presentAgreement({},[53],async()=>{credentials++;}),{code:'LINE_REGISTRATION_UNSUPPORTED'});assert.equal(credentials,0);
 choice=R.ACCEPTED;assert.equal(await port.presentAgreement({},[47],async()=>({endpoint:'https://legy.line.test/S4',headers:{'X-Line-Access':'pending-secret'}})),undefined);
 assert.equal(seen.at(-1)[2][0].headerValue,'pending-secret');
});
test('actual registration window disposes late mount and never opens after ability destruction',async()=>{
 for(const phase of ['lookup','mount']){
  let lookup,open,closed=0,disposed=0,cancelled=0,monitor;
  const prompt={openCustomDialog:()=>new Promise(r=>open=r),closeCustomDialog:async()=>{closed++;}};
  const host={getUIContext:()=>({getPromptAction:()=>prompt})};
  const context={};const load=createLoader({}, {},{getLastWindow:()=>phase==='lookup'?new Promise(r=>lookup=r):Promise.resolve(host)},undefined,undefined,undefined,{'@kit.ArkUI':{ComponentContent:class{dispose(){disposed++;}}}});
  const {HostLifecycleMonitor}=load('main/ets/core/HostLifecycleMonitor');HostLifecycleMonitor.initialize(m=>{monitor=m;return 1;});monitor.onAbilityCreate({context});monitor.onAbilityForeground({context});
  const {LineRegistrationWindow}=load(base+'registration/ui/LineRegistrationWindow');global.DialogAlignment={Center:0};
  const owned=new LineRegistrationWindow(context);const mounting=owned.open({},()=>({}),()=>cancelled++);await tick();monitor.onAbilityDestroy({context});
  if(phase==='lookup')lookup(host);else open();await mounting;await tick();
  assert.equal(cancelled,1);assert.equal(closed,phase==='lookup'?0:1);assert.equal(disposed,phase==='lookup'?0:1);assert.equal(owned.isActive(),false);
 }
});

test('late rejected registration mount disposes its own content without closing a replacement',async()=>{
 let monitor;const pending=[],closed=[],disposed=[];let id=0;
 const prompt={openCustomDialog:()=>new Promise((resolve,reject)=>pending.push({resolve,reject})),closeCustomDialog:async content=>{closed.push(content.id);}};
 const context={},host={getUIContext:()=>({getPromptAction:()=>prompt})};
 const load=createLoader({}, {},{getLastWindow:async()=>host},undefined,undefined,undefined,{'@kit.ArkUI':{ComponentContent:class{constructor(){this.id=++id;}dispose(){disposed.push(this.id);}}}});
 const {HostLifecycleMonitor}=load('main/ets/core/HostLifecycleMonitor');HostLifecycleMonitor.initialize(m=>{monitor=m;return 1;});monitor.onAbilityCreate({context});monitor.onAbilityForeground({context});
 const {LineRegistrationWindow}=load(base+'registration/ui/LineRegistrationWindow');global.DialogAlignment={Center:0};
 const owned=new LineRegistrationWindow(context);const first=owned.open({},()=>({}),()=>{});first.catch(()=>{});await tick();await owned.hide();
 const second=owned.open({},()=>({}),()=>{});await tick();pending[0].reject(Error('old mount failed'));await assert.rejects(first);await tick();
 assert.deepEqual(disposed,[1]);assert.equal(owned.isActive(),true);assert.ok(!closed.includes(2));
 pending[1].resolve();await second;assert.deepEqual(disposed,[1]);await owned.hide();assert.deepEqual(disposed,[1,2]);
});

test('registration request during deferred return-to-login cleanup cannot be completed by QR', async () => {
  const h = harness(), p = presenter(), r = presenter(p.context);
  let qrDone, finishHide;
  p.show = async actions => { p.actions = actions; };
  p.registrationPresenter = () => r;
  h.account.startQrLogin = () => new Promise(resolve => { qrDone = resolve; });
  const ordinary = h.c.request(p);
  await tick();
  p.actions.register();
  await tick();
  r.hide = () => new Promise(resolve => { finishHide = resolve; });
  r.back();
  await tick();
  const duringReturn = h.c.requestRegistration(presenter(p.context));
  duringReturn.result.catch(() => {});
  finishHide();
  await tick();
  qrDone('qr-account');
  await ordinary.result;
  await assert.rejects(duringReturn.result, { code: 'LINE_LOGIN_IN_PROGRESS' });
});

test('actual ordinary login view exposes a localized registration button and clears inputs before dispatch', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
  const source = fs.readFileSync(path.join(__dirname,
    '../src/main/ets/vendors/line/auth/ui/LineLoginView.ets'), 'utf8');
  const parsed = ts.createSourceFile('LineLoginView.ts', source.replace('struct LineLoginView', 'class LineLoginView'),
    ts.ScriptTarget.ES2021, true);
  const view = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'LineLoginView');
  assert.ok(view);
  const build = view.members.find(node => ts.isMethodDeclaration(node) && node.name?.text === 'build');
  const entry = view.members.find(node => ts.isMethodDeclaration(node) && node.name?.text === 'registrationAction');
  assert.ok(entry, 'actual registration entry builder must exist');
  function collect(node, predicate, found = []) {
    if (predicate(node)) found.push(node);
    ts.forEachChild(node, child => { collect(child, predicate, found); });
    return found;
  }
  assert.ok(collect(build, node => ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
    node.expression.name.text === 'registrationAction').length, 'real build must include the registration entry');
  const click = collect(entry, node => ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
    node.expression.name.text === 'onClick').find(node => collect(node.expression, child =>
      ts.isStringLiteral(child) && child.text === 'app.string.mp_line_registration_title').length);
  assert.ok(click, 'resource-backed registration Button must own an onClick callback');
  const callback = click.arguments[0];
  const modelClass = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'LineLoginViewModel');
  const members = modelClass.members.map(node => ts.isPropertyDeclaration(node) ?
    ts.factory.updatePropertyDeclaration(node, node.modifiers?.filter(modifier => !ts.isDecorator(modifier)),
      node.name, node.questionToken, node.type, node.initializer) : node);
  const modelSource = ts.createPrinter().printNode(ts.EmitHint.Unspecified,
    ts.factory.createClassDeclaration(undefined, 'LineLoginViewModel', undefined, undefined, members), parsed);
  const modelJs = ts.transpileModule(modelSource, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
  const Model = new Function(`${modelJs};return LineLoginViewModel;`)();
  const model = new Model();
  model.email = 'private@example.test'; model.password = 'private-password';
  let calls = 0;
  const receiver = { params: { model, actions: { register() {
    calls++;
    assert.equal(model.email, ''); assert.equal(model.password, '');
  } } } };
  const callbackJs = ts.transpileModule(`const click = ${callback.getText(parsed)};`,
    { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
  new Function(`${callbackJs};return click;`).call(receiver)();
  assert.equal(calls, 1);
});

function registrationViewSource() {
  const fs = require('node:fs'), path = require('node:path');
  const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
  const source = fs.readFileSync(path.join(__dirname,
    '../src/main/ets/vendors/line/registration/ui/LineRegistrationView.ets'), 'utf8');
  const parsed = ts.createSourceFile('LineRegistrationView.ts', source.replace('struct LineRegistrationView', 'class LineRegistrationView'),
    ts.ScriptTarget.ES2021, true);
  const view = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'LineRegistrationView');
  function collect(node, predicate, found = []) {
    if (predicate(node)) found.push(node);
    ts.forEachChild(node, child => { collect(child, predicate, found); });
    return found;
  }
  return { ts, parsed, view, collect };
}

test('actual verification View branches on PULL destination and permits local-device copying of both handoff values', () => {
  const { ts, parsed, view, collect } = registrationViewSource();
  const verification = view.members.find(node => ts.isMethodDeclaration(node) && node.name?.text === 'verification');
  const branch = collect(verification, node => ts.isIfStatement(node) && ts.isPropertyAccessExpression(node.expression) &&
    node.expression.name.text === 'destinationPhoneNumber')[0];
  assert.ok(branch?.elseStatement, 'PULL state must select instructions with a code-entry alternative');
  const condition = new Function(`return ${branch.expression.getText(parsed)};`);
  assert.equal(condition.call({ params: { model: { state: { destinationPhoneNumber: '+1555000' } } } }), '+1555000');
  assert.equal(condition.call({ params: { model: { state: {} } } }), undefined);
  assert.ok(collect(branch.elseStatement, node => ts.isStringLiteral(node) && node.text === 'app.string.mp_line_registration_code').length);
  assert.ok(collect(branch.elseStatement, node => ts.isPropertyAccessExpression(node) && node.name.text === 'submitCode').length);
  const copies = collect(branch.thenStatement, node => ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
    node.expression.name.text === 'copyOption');
  assert.equal(copies.length, 2);
  for (const [index, field] of ['destinationPhoneNumber', 'pinCodeMessage'].entries()) {
    assert.ok(collect(copies[index].expression, node => ts.isPropertyAccessExpression(node) && node.name.text === field).length);
    assert.equal(copies[index].arguments[0].getText(parsed), 'CopyOptions.LocalDevice');
  }
});

test('actual model maps stable errors to localized actionable copy and the View renders that mapping', () => {
  const { LineRegistrationViewModel } = createLoader()(base + 'registration/ui/LineRegistrationViewModel');
  const model = new LineRegistrationViewModel();
  const groups = {
    error_unsupported: ['UNSUPPORTED', 'RULE_UNSUPPORTED'], error_upgrade: ['APP_UPGRADE_REQUIRED'],
    error_reset: ['INVALID_CONTEXT', 'NOT_FOUND', 'INVALID_STATE'], error_verification: ['VERIFICATION_FAILED'],
    error_retry_later: ['RETRY_LATER'], error_input: ['ILLEGAL_ARGUMENT', 'PASSWORD_INVALID'],
    error_not_allowed: ['NOT_ALLOWED'], error_account_conflict: ['ACCOUNT_CONFLICT'],
    challenge: ['HUMAN_VERIFICATION_REQUIRED'], pending: ['INCOMPLETE'], uncertain: ['CREATION_UNCERTAIN']
  };
  const fs = require('node:fs'), path = require('node:path');
  const resources = ['base', 'zh_CN'].map(locale => new Map(JSON.parse(fs.readFileSync(path.join(__dirname,
    '../src/main/resources', locale, 'element/string.json'), 'utf8')).string.map(item => [item.name, item.value])));
  for (const [key, codes] of Object.entries(groups)) for (const suffix of codes) {
    model.update({ stage: 'verification', errorCode: 'LINE_REGISTRATION_' + suffix });
    const message = model.errorMessage();
    assert.equal(message.name, 'app.string.mp_line_registration_' + key);
    for (const localized of resources) assert.ok(localized.get('mp_line_registration_' + key), key);
  }
  for (const errorCode of [undefined, 'unknown-private-server-text', 'LINE_REGISTRATION_FAILED']) {
    model.update({ stage: 'verification', errorCode });
    assert.equal(model.errorMessage().name, 'app.string.mp_line_registration_error');
  }
  for (const stage of ['countrySelection', 'phoneInput']) {
    model.update({ stage, errorCode: 'LINE_REGISTRATION_UNSUPPORTED' });
    assert.equal(model.errorMessage().name, 'app.string.mp_line_registration_error_country');
    for (const localized of resources) assert.ok(localized.get('mp_line_registration_error_country'));
  }
  model.update({ stage: 'verification', errorCode: 'LINE_RPC_RETRY_LATER' });
  assert.equal(model.errorMessage().name, 'app.string.mp_line_registration_error_retry_later');
  const { ts, view, collect } = registrationViewSource();
  const build = view.members.find(node => ts.isMethodDeclaration(node) && node.name?.text === 'build');
  assert.ok(collect(build, node => ts.isCallExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === 'Text' &&
    collect(node, child => ts.isPropertyAccessExpression(child) && child.name.text === 'errorMessage').length).length,
  'actual form must render the model error resource');
});
