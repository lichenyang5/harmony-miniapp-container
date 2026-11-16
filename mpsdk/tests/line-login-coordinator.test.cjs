const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const tick = () => new Promise(setImmediate);
function presenter(context = {}) { return {context, shown:0, hidden:0, states:[], async show(actions) {this.actions=actions;this.shown++;}, update(state) {this.states.push(state);}, async hide(){this.hidden++;}}; }
test('restore hit never opens UI and reuseOnly miss fails', async () => {
  const { LineLoginCoordinator } = createLoader()('main/ets/vendors/line/auth/LineLoginCoordinator');
  const p=presenter(); await LineLoginCoordinator.forAccount({getVersion:()=>1,restoreSession:async()=>true}).request(p).result;
  assert.equal(p.shown,0);
  await assert.rejects(LineLoginCoordinator.forAccount({getVersion:()=>1,restoreSession:async()=>false}).request(p,true).result,{code:'LINE_LOGIN_REQUIRED'});
});
test('shared waiters cancel independently; another ability cannot steal flow; hide before success', async () => {
  const { LineLoginCoordinator } = createLoader()('main/ets/vendors/line/auth/LineLoginCoordinator');
  let finish, cancels=0;
  const account={getVersion:()=>1,restoreSession:async()=>false, startQrLogin(state,started){started(1);return new Promise(r=>finish=r);},cancelLogin(){cancels++;}};
  const c=LineLoginCoordinator.forAccount(account), p=presenter(), p2=presenter(p.context);
  const a=c.request(p), b=c.request(p2); await tick();
  assert.equal(p.shown,1); assert.equal(p2.shown,0); assert.equal(p.states[0].phase,'loading');
  await assert.rejects(c.request(presenter()).result,{code:'LINE_LOGIN_IN_PROGRESS'});
  a.cancel(); await assert.rejects(a.result,{code:'LINE_LOGIN_CANCELLED'}); assert.equal(cancels,0);
  finish('mid'); await b.result; assert.equal(p.hidden,1);
});
test('last waiter cancellation closes UI and stale attempt cannot close new flow', async () => {
  const { LineLoginCoordinator } = createLoader()('main/ets/vendors/line/auth/LineLoginCoordinator');
  let count=0; const finishes=[];
  const account={getVersion:()=>1,restoreSession:async()=>false,startQrLogin(state,started){started(++count);return new Promise(r=>finishes.push(r));},cancelLogin(){}};
  const c=LineLoginCoordinator.forAccount(account), p=presenter(); const a=c.request(p); await tick();
  a.cancel(); await assert.rejects(a.result); await tick(); assert.equal(p.hidden,1);
  const next=presenter(), b=c.request(next); await tick(); finishes[0]('old'); await tick(); assert.equal(next.hidden,0);
  finishes[1]('new'); await b.result; assert.equal(next.hidden,1);
});
test('reuseOnly joining interactive login fails immediately without becoming a waiter', async () => {
  const { LineLoginCoordinator } = createLoader()('main/ets/vendors/line/auth/LineLoginCoordinator');
  let finish; const account={getVersion:()=>1,restoreSession:async()=>false,startQrLogin(){return new Promise(r=>finish=r);},cancelLogin(){}};
  const c=LineLoginCoordinator.forAccount(account), p=presenter(); const a=c.request(p); await tick();
  await assert.rejects(c.request(presenter(p.context),true).result,{code:'LINE_LOGIN_REQUIRED'});
  finish('mid'); await a.result;
});
test('cancel during pending show rejects promptly then hides late dialog before allowing next flow', async () => {
  const { LineLoginCoordinator } = createLoader()('main/ets/vendors/line/auth/LineLoginCoordinator');
  let shown, starts=0; const account={getVersion:()=>1,restoreSession:async()=>false,startQrLogin(){starts++;},cancelLogin(){}};
  const c=LineLoginCoordinator.forAccount(account), p=presenter(); p.show=()=>new Promise(r=>shown=r);
  const a=c.request(p); await tick(); a.cancel(); await assert.rejects(a.result,{code:'LINE_LOGIN_CANCELLED'});
  assert.equal(p.hidden,0); shown(); await tick(); assert.equal(p.hidden,1); assert.equal(starts,0);
});
test('presentation exceptions clean partial UI and restore failures do not create login', async () => {
  const { LineLoginCoordinator } = createLoader()('main/ets/vendors/line/auth/LineLoginCoordinator');
  const p=presenter(); p.show=async()=>{throw new Error('private');};
  await assert.rejects(LineLoginCoordinator.forAccount({getVersion:()=>1,restoreSession:async()=>false}).request(p).result,{code:'LINE_LOGIN_FAILED'});
  assert.equal(p.hidden,1);
  const p2=presenter(); await assert.rejects(LineLoginCoordinator.forAccount({getVersion:()=>1,restoreSession:async()=>{throw new Error('private');}}).request(p2,true).result);
  assert.equal(p2.shown,0);
});
test('interactive restore failure shows retry UI and retry restores without starting login', async () => {
  const { LineLoginCoordinator } = createLoader()('main/ets/vendors/line/auth/LineLoginCoordinator');
  let restores=0, logins=0;
  const account={getVersion:()=>1,getAccountId:()=> 'restored',restoreSession:async()=>{if(++restores===1)throw new Error('network');return true;},startQrLogin(){logins++;},cancelLogin(){}};
  const p=presenter(); const request=LineLoginCoordinator.forAccount(account).request(p);
  await tick(); assert.equal(p.shown,1); assert.equal(p.states.at(-1).phase,'failed'); assert.equal(logins,0);
  p.actions.retry(); await request.result; assert.equal(restores,2); assert.equal(logins,0); assert.equal(p.hidden,1);
});
test('success waits for hide and hide failure rejects without removing authenticated account', async () => {
  const { LineLoginCoordinator } = createLoader()('main/ets/vendors/line/auth/LineLoginCoordinator');
  let finish, hide; const account={getVersion:()=>1,restoreSession:async()=>false,startQrLogin(){return new Promise(r=>finish=r);},cancelLogin(){}};
  const p=presenter(); p.hide=()=>new Promise(r=>hide=r); let done=false;
  const result=LineLoginCoordinator.forAccount(account).request(p).result.then(()=>done=true);
  await tick(); finish('mid'); await tick(); assert.equal(done,false); hide(); await result;
  const p2=presenter(); p2.hide=async()=>{throw new Error('view');};
  const result2=LineLoginCoordinator.forAccount(account).request(p2).result; await tick(); finish('mid');
  await assert.rejects(result2,{code:'LINE_LOGIN_UI_FAILED'});
});
test('account changing while success hides dialog rejects stale login success', async () => {
  const { LineLoginCoordinator } = createLoader()('main/ets/vendors/line/auth/LineLoginCoordinator');
  let finish, hide, version=1;
  const account={getVersion:()=>version,restoreSession:async()=>false,startQrLogin(){return new Promise(r=>finish=r);},cancelLogin(){}};
  const p=presenter(); p.hide=()=>new Promise(r=>hide=r);
  const result=LineLoginCoordinator.forAccount(account).request(p).result;
  await tick(); finish('mid'); await tick(); version++; hide();
  await assert.rejects(result,{code:'LINE_LOGIN_CANCELLED'});
});
