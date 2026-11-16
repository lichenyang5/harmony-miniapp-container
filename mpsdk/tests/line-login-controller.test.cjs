const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
test('switching method cancels only owned attempt and stale completion cannot settle result', async () => {
  const { LineLoginController } = createLoader()('main/ets/vendors/line/auth/LineLoginController');
  let qrResolve, emailResolve, qrState;
  const cancellations = [], states = [];
  const account = {
    startQrLogin(state, started) { qrState = state; started(7); return new Promise(r => qrResolve = r); },
    startEmailLogin(email, password, state, started) { started(8); state({kind:'pinReady',pin:'1234'}); return new Promise(r => emailResolve = r); },
    cancelLogin(version) { cancellations.push(version); }
  };
  const controller = new LineLoginController(account, state => states.push(state));
  let done = false;
  const result = controller.start().then(mid => { done = true; return mid; });
  qrState({kind:'qrReady',url:'qr'});
  qrState({kind:'qrVerified'});
  assert.equal(states.at(-1).phase, 'confirming');
  assert.equal(states.at(-1).qrUrl, undefined);
  controller.showEmail(); controller.submitEmail('email','password');
  qrResolve('old'); await Promise.resolve();
  assert.equal(done, false); assert.deepEqual(cancellations,[7]);
  assert.equal(states.at(-1).phase,'pin');
  emailResolve('current'); assert.equal(await result,'current'); controller.dispose();
});
test('failed login stays pending for explicit retry and cancel rejects promptly', async () => {
  const { LineLoginController } = createLoader()('main/ets/vendors/line/auth/LineLoginController');
  const states = []; let attempts = 0;
  const controller = new LineLoginController({ startQrLogin() { attempts++; return Promise.reject(new Error('private')); }, cancelLogin() {} }, state => states.push(state));
  const pending = controller.start(); await new Promise(setImmediate);
  assert.equal(states.at(-1).phase,'failed'); assert.equal(attempts,1);
  controller.retry(); await new Promise(setImmediate); assert.equal(attempts,2);
  controller.cancel(); await assert.rejects(pending, {code:'LINE_LOGIN_CANCELLED'});
});
test('authorized callback and throwing observer cannot complete authentication before manager result', async () => {
  const { LineLoginController } = createLoader()('main/ets/vendors/line/auth/LineLoginController');
  let finish, state, settled=false;
  const c=new LineLoginController({startQrLogin(onState,started){state=onState;started(4);return new Promise(r=>finish=r);},cancelLogin(){}},()=>{throw new Error('view');});
  const result=c.start().then(mid=>{settled=true;return mid;});
  state({kind:'authorized',mid:'early'}); await Promise.resolve(); assert.equal(settled,false);
  finish('final'); assert.equal(await result,'final');
});
test('restore retry failures stay pending and method switch discards stale restoration', async () => {
  const load=createLoader(); const { LineLoginController }=load('main/ets/vendors/line/auth/LineLoginController');
  const {MiniAppError}=load('main/ets/core/MiniAppError'); let finishRestore, finishQr, qr=0;
  const account={restoreSession:()=>new Promise(r=>finishRestore=r),getAccountId:()=> 'old',startQrLogin(){qr++;return new Promise(r=>finishQr=r);},cancelLogin(){}};
  const states=[]; const c=new LineLoginController(account,state=>states.push(state));
  let settled=false; const result=c.start(new MiniAppError('LINE_ACCOUNT_RESTORE_FAILED','restore')).then(mid=>{settled=true;return mid;});
  assert.equal(states.at(-1).phase,'failed'); assert.equal(qr,0); c.retry(); c.showQr(); finishRestore(true);
  await tick(); assert.equal(settled,false); finishQr('new'); assert.equal(await result,'new');
});
function tick(){return new Promise(setImmediate);}
test('restore retry failure remains retryable and restore miss alone starts QR', async () => {
  const load=createLoader(); const {LineLoginController}=load('main/ets/vendors/line/auth/LineLoginController');
  const {MiniAppError}=load('main/ets/core/MiniAppError'); let restores=0, qr=0, finish;
  const states=[]; const c=new LineLoginController({restoreSession:async()=>{if(++restores===1)throw new Error('network');return false;},startQrLogin(){qr++;return new Promise(r=>finish=r);},cancelLogin(){}},s=>states.push(s));
  const result=c.start(new MiniAppError('LINE_ACCOUNT_RESTORE_FAILED','restore'));
  c.retry(); await tick(); assert.equal(states.at(-1).phase,'failed'); assert.equal(qr,0);
  c.retry(); await tick(); assert.equal(qr,1); finish('mid'); assert.equal(await result,'mid');
});
