const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');

function fixture() {
  const load = createLoader();
  const { MiniAppSession } = load('main/ets/core/Runtime');
  const { WebSchemeDecision: D } = load('main/ets/web/scheme/WebSchemeTypes');
  function create(id, createBinding) {
    return new MiniAppSession(id, { info: { appId:'same-app', vendor:'test', url:'https://example.com/' },
      adapter: { vendorId:'test' }, vendor:{vendorId:'test', createBinding},
      swipeBackController:{ dispose(){} } }, {});
  }
  function attach(session) { session.attach({ evaluate:async()=>'' });session.beginDocument('https://example.com/'); }
  const navigate = (session, documentId=session.getDocumentId()) =>
    session.interceptWebScheme({ url:'custom://command', isMainFrame:true, documentId });
  return { create, attach, navigate, D };
}

test('session creates independent navigation handlers once, guards stale requests and keeps registrations across documents', () => {
  const f=fixture();let factories=0;const calls=[];
  const binding = session => ({ onDocumentChanged(){}, dispose(){}, createWebSchemeHandlers() {
    factories++;
    return [{id:'test.custom',supports: request => /^custom:/i.test(request.url),handle:request=>{calls.push([session.id,request.documentId]);return f.D.CONSUME;}}];
  }});
  const first=f.create('first',binding);const second=f.create('second',binding);
  assert.equal(factories,2);
  assert.equal(f.navigate(first),true);assert.deepEqual(calls,[]);
  f.attach(first);f.attach(second);
  assert.equal(f.navigate(first,0),true);assert.deepEqual(calls,[]);
  assert.equal(f.navigate(first),true);
  first.beginDocument('https://example.com/next');assert.equal(f.navigate(first),true);
  assert.deepEqual(calls,[['first',1],['first',2]]);
  first.close();assert.equal(f.navigate(first),true);
  assert.equal(f.navigate(second),true);assert.deepEqual(calls.at(-1),['second',1]);
  assert.equal(factories,2);second.close();
});

test('session resets handlers before Binding notification and releases every handler before the Binding', () => {
  const f=fixture();const events=[];
  const session=f.create('lifecycle',()=>({
    createWebSchemeHandlers:()=>[
      {id:'one',supports: request => /^custom:/i.test(request.url),handle:(request,chain)=>chain.proceed(),reset(){events.push('reset1');throw new Error('private');},dispose(){events.push('dispose1');throw new Error('private');}},
      {id:'two',supports: request => /^custom:/i.test(request.url),handle:()=>f.D.CONSUME,reset(){events.push('reset2');},dispose(){events.push('dispose2');}}
    ],
    onDocumentChanged(){events.push('binding.changed');},dispose(){events.push('binding.disposed');}
  }));
  f.attach(session);assert.deepEqual(events,['reset1','reset2','binding.changed']);
  session.close();session.close();
  assert.deepEqual(events.slice(3),['dispose1','dispose2','binding.disposed']);
});

test('navigation that changes its Session document cannot fall through to another handler', () => {
  const f=fixture();let second=0;
  const session=f.create('reentrant',owner=>({onDocumentChanged(){},dispose(){},createWebSchemeHandlers:()=>[
    {id:'first',supports: request => /^custom:/i.test(request.url),handle(request,chain){owner.beginDocument('https://example.com/next');return chain.proceed();}},
    {id:'second',supports: request => /^custom:/i.test(request.url),handle(){second++;return f.D.CONSUME;}}
  ]}));
  f.attach(session);assert.equal(f.navigate(session),true);assert.equal(second,0);
  session.close();
});

test('handler factory failures still dispose the Binding and reject Session creation', () => {
  const f=fixture();let disposed=0;const cause=new Error('private setup failure');
  assert.throws(()=>f.create('failed',()=>({onDocumentChanged(){},dispose(){disposed++;},
    createWebSchemeHandlers(){throw cause;}
  })),error=>error.code==='VENDOR_BINDING_FAILED'&&error.originalCause===cause);
  assert.equal(disposed,1);
});

test('a document change inside reset notifies the latest document after every handler is reset', () => {
  const f = fixture();
  const events = [];
  let reentered = false;
  const session = f.create('reset-reentrant', owner => ({
    createWebSchemeHandlers: () => [
      { id: 'first', supports: request => /^custom:/i.test(request.url), handle: (request, chain) => chain.proceed(), reset() {
        events.push('reset.first');
        if (!reentered) {
          reentered = true;
          owner.beginDocument('https://example.com/latest');
        }
      } },
      { id: 'second', supports: request => /^custom:/i.test(request.url), handle: (request, chain) => chain.proceed(),
        reset() { events.push('reset.second'); } }
    ],
    onDocumentChanged(documentId) { events.push(`binding.${documentId}`); },
    dispose() {}
  }));
  f.attach(session);
  assert.deepEqual(events, ['reset.first', 'reset.second', 'binding.2']);
  session.close();
});
