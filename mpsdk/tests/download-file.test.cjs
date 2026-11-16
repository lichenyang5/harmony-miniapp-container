const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const strings = require('../src/main/resources/base/element/string.json').string;
const flush = () => new Promise(r => setImmediate(r));
const bytes = (...values) => new Uint8Array(values).buffer;
function text(value) {
  return value.params.reduce((s, p) => s.replace('%s', String(p)),
    strings.find(s => s.name === value.name.split('.').pop()).value);
}
function fixture() {
  const jobs = [], calls = [], files = new Set(), dirs = new Set(); let gate, windowGate, cancel = false, writeError = false;
  let fd = 0, closeError = false, requestError, holdDialogs = false;
  const dialogs = [];
  const host = {cacheDir:'/cache', applicationInfo:{accessTokenId:1}};
  const load = createLoader({}, {}, {}, {}, () => true, {DEBUG:false}, {
    '@kit.NetworkKit': {http:{RequestMethod:{GET:'GET'}, createHttp() {
      const callbacks = new Map(); let resolve, reject;
      const pending = new Promise((a,b) => {resolve=a;reject=b;});
      const job = { callbacks, resolve, reject, destroyed:0,
        on(n, f) {callbacks.set(n,f);}, off(n) {callbacks.delete(n);},
        requestInStream(url, options) { calls.push({url,options}); if(requestError) throw requestError; return pending; },
        destroy() {this.destroyed++;} };
      jobs.push(job); return job;
    }}},
    '@kit.ArkUI': {window:{async getLastWindow() {if(windowGate) await windowGate; return {getUIContext(){return {
      showAlertDialog(options) {calls.push(options); dialogs.push(options);
        if(!holdDialogs) (cancel ? options.primaryButton : options.secondaryButton).action();}
    };}};}}},
    '@kit.CoreFileKit': {
      picker:{DocumentSaveOptions:class {},DocumentPickerMode:{DOWNLOAD:1},DocumentViewPicker:class {
        async save(){if(gate) await gate; return ['file://docs/Download/app'];}
      }},
      fileUri:{FileUri:class {constructor(value){if(typeof value!=='string') throw {code:401};
        this.path=value.replace('file://docs','');this.name=value.split('/').pop();}}},
      fileIo:{OpenMode:{CREATE:64,READ_WRITE:2},
        accessSync(path){return files.has(path) || dirs.has(path);},
        mkdirSync(path){calls.push(['mkdir',path]);if(files.has(path)||dirs.has(path)) throw {code:13900015};dirs.add(path);},
        statSync(path){return {isDirectory(){return dirs.has(path);}};},
        openSync(path){assert.ok(!files.has(path));files.add(path);calls.push(['open',path]);return {fd:++fd};},
        writeSync(fd, chunk){if(writeError) throw {code:13900028};
          const data=Array.from(new Uint8Array(chunk)).slice(0,2);calls.push(['write',fd,data]);return data.length;},
        closeSync(file){calls.push(['close',file.fd]);if(closeError) throw {code:13900005};},unlinkSync(path){files.delete(path);calls.push(['unlink',path]);}
      }
    }
  });
  const {DownloadTools} = load('main/ets/capabilities/files/DownloadTools');
  const {VkMediaHandler} = load('main/ets/vendors/vk/handlers/VkMediaHandler');
  const context={uiAbilityContext:host,getDocumentId(){return 1;},addCleanup(){}};
  return {load,host,jobs,calls,files,dirs,dialogs,holdDialogs(){holdDialogs=true;},tools:new DownloadTools(host),handler:new VkMediaHandler(context),
    rejectRequest(error){requestError=error;},cancel(){cancel=true;},defer(p){gate=p;},deferWindow(p){windowGate=p;},failWrite(){writeError=true;},failClose(){closeError=true;}};
}
const params={url:'https://example.test/a',filename:'a.zip'};

async function complete(job, status=200) {
  job.callbacks.get('dataEnd')(); job.resolve(status); await flush();
}

test('HTTP promise waits for all bytes, successful status and file close',async()=>{
  const f=fixture();let settled=false;
  const pending=f.tools.start(params.url,params.filename).then(()=>{settled=true;});await flush();
  const j=f.jobs[0];assert.equal(settled,false);
  j.callbacks.get('dataReceive')(bytes(1,2,3,4,5));
  j.callbacks.get('dataEnd')();await flush();assert.equal(settled,false);
  j.resolve(200);await pending;
  assert.equal(settled,true);assert.equal(j.destroyed,1);
  assert.deepEqual(f.calls.filter(c=>c[0]==='write').flatMap(c=>c[2]),[1,2,3,4,5]);
  assert.equal(f.calls.filter(c=>c[0]==='close').length,1);
  assert.ok(f.files.has('/Download/app/a.zip'));
});

test('HTTP headers alone do not complete; disposal preserves in-flight transfer',async()=>{
  const f=fixture();let settled=false;
  const pending=f.tools.start(params.url,params.filename).then(()=>{settled=true;});await flush();
  f.tools.dispose();const j=f.jobs[0];j.resolve(200);await flush();assert.equal(settled,false);
  j.callbacks.get('dataReceive')(bytes(9));j.callbacks.get('dataEnd')();await pending;
  await assert.rejects(f.tools.start(params.url,params.filename));
});

test('HTTP error, network abort, write and close failures reject after cleanup exactly once',async()=>{
  for(const mode of ['status','network','write','close']){
    const f=fixture();const pending=f.tools.start(params.url,params.filename);
    const rejected=assert.rejects(pending);await flush();const j=f.jobs[0];const end=j.callbacks.get('dataEnd');
    if(mode==='write') f.failWrite();
    if(mode==='close') f.failClose();
    j.callbacks.get('dataReceive')(bytes(1));
    if(mode==='network'||mode==='write') j.reject({code:2300999});
    else {end();j.resolve(mode==='status'?404:200);}
    await rejected;end();await flush();
    assert.equal(j.destroyed,1);assert.equal(j.callbacks.size,0);
    assert.equal(f.calls.filter(c=>c[0]==='unlink').length,1);
    assert.equal(f.calls.filter(c=>c[0]==='close').length,1);assert.equal(f.files.size,0);
  }
});

test('HTTP saves directly and numbers before extension for existing and concurrent files',async()=>{
  const f=fixture();f.files.add('/Download/app/a.zip');f.files.add('/Download/app/a (1).zip');
  const first=f.tools.start(params.url,'a.zip'), second=f.tools.start(params.url,'a.zip');await flush();
  assert.deepEqual(f.calls.filter(c=>c[0]==='open').map(c=>c[1]),['/Download/app/a (2).zip','/Download/app/a (3).zip']);
  for(const j of f.jobs) await complete(j);await Promise.all([first,second]);
  assert.ok(f.files.has('/Download/app/a.zip'));assert.ok(f.files.has('/Download/app/a (1).zip'));
});

test('HTTP naming handles no extension, dotfile and multiple dots',async()=>{
  for(const [name,expected] of [['README','README (1)'],['.env','.env (1)'],['a.tar.gz','a.tar (1).gz']]){
    const f=fixture();f.files.add('/Download/app/'+name);
    const pending=f.tools.start(params.url,name);await flush();
    assert.equal(f.calls.find(c=>c[0]==='open')[1],'/Download/app/'+expected);
    await complete(f.jobs[0]);await pending;
  }
});

test('HTTP directory await respects disposal before opening file',async()=>{
  const f=fixture();let resolve;f.defer(new Promise(r=>resolve=r));
  const pending=f.tools.start(params.url,params.filename);f.tools.dispose();resolve();
  await assert.rejects(pending);assert.equal(f.jobs.length,0);assert.equal(f.files.size,0);
});

test('VK owns resource dialog and CANCEL prevents HTTP creation',async()=>{
  const f=fixture();f.cancel();await assert.rejects(f.handler.downloadFile(params));
  const d=f.calls[0];assert.equal(text(d.title),'File Download');
  assert.equal(text(d.message),'Do you want to save a.zip to your devices?');
  assert.deepEqual([text(d.primaryButton.value),text(d.secondaryButton.value)],['CANCEL','SAVE']);
  assert.equal('fontColor' in d.primaryButton,false);assert.equal(f.jobs.length,0);
});

test('VK queued confirmations expire after disposal during window lookup',async()=>{
  const f=fixture();let resolve;f.deferWindow(new Promise(r=>resolve=r));
  const pending=f.handler.downloadFile(params);
  const firstRejected=assert.rejects(pending);
  const secondRejected=assert.rejects(f.handler.downloadFile(params));
  f.handler.dispose();resolve();await Promise.all([firstRejected,secondRejected]);assert.equal(f.calls.length,0);
});

function bridge(f) {
  const scripts=[];const {createTestSession}=require('./test-session.cjs');
  const session=createTestSession(f.load,{host:f.host,onScript:s=>scripts.push(s)});
  const proxy=session.getBinding().injections[0].object;
  const send=id=>proxy.onInterceptRequest(JSON.stringify({type:'vk-connect',handler:'VKWebAppDownloadFile',
    params:{...params,request_id:id}}),id);
  return {scripts,session,send};
}

test('VK queues simultaneous confirmations and downloads concurrently with isolated replies and files',async()=>{
  const f=fixture();f.holdDialogs();const b=bridge(f);
  const logs=[];f.load('main/ets/logging/SdkLogger').SdkLogger.install({
    write(level,event,details){logs.push({event,...JSON.parse(details)});}
  });
  b.send('first');b.send('second');await flush();
  assert.equal(b.scripts.length,0);assert.equal(f.dialogs.length,1);
  f.dialogs[0].secondaryButton.action();await flush();
  assert.equal(f.jobs.length,1);assert.equal(f.dialogs.length,2);
  f.dialogs[1].secondaryButton.action();await flush();
  assert.equal(f.jobs.length,2);assert.equal(b.scripts.length,0);
  assert.deepEqual(f.calls.filter(c=>c[0]==='open').map(c=>c[1]),
    ['/Download/app/a.zip','/Download/app/a (1).zip']);
  f.jobs[0].callbacks.get('dataReceive')(bytes(1,2));
  f.jobs[1].callbacks.get('dataReceive')(bytes(3,4));
  f.jobs[0].callbacks.get('dataReceiveProgress')({receiveSize:2,totalSize:10});
  f.jobs[1].callbacks.get('dataReceiveProgress')({receiveSize:2,totalSize:20});
  const progress=logs.filter(l=>l.event.startsWith('DownloadTools.downloadProgress'));
  assert.equal(new Set(progress.map(l=>l.requestId)).size,2);
  assert.deepEqual(progress.map(l=>l.event),['DownloadTools.downloadProgress 2/10 bytes (20%)',
    'DownloadTools.downloadProgress 2/20 bytes (10%)']);
  f.jobs[1].reject({code:2300999});await flush();
  assert.equal(b.scripts.length,1);assert.ok(b.scripts[0].includes('second'));
  assert.ok(b.scripts[0].includes('VKWebAppDownloadFileFailed'));
  assert.equal(f.jobs[0].destroyed,0);assert.ok(f.files.has('/Download/app/a.zip'));
  assert.equal(f.files.has('/Download/app/a (1).zip'),false);
  await complete(f.jobs[0]);assert.equal(b.scripts.length,2);
  assert.ok(b.scripts[1].includes('first'));assert.ok(b.scripts[1].includes('VKWebAppDownloadFileResult'));
  assert.deepEqual(f.calls.filter(c=>c[0]==='write'),[['write',1,[1,2]],['write',2,[3,4]]]);
  b.session.close();
});

test('VK cancelling one confirmation still presents the next queued request',async()=>{
  const f=fixture();f.holdDialogs();const b=bridge(f);
  b.send('cancelled');b.send('saved');await flush();
  assert.equal(b.scripts.length,0);
  f.dialogs[0].primaryButton.action();await flush();
  assert.equal(b.scripts.length,1);assert.ok(b.scripts[0].includes('cancelled'));
  assert.equal(f.dialogs.length,2);assert.equal(f.jobs.length,0);
  f.dialogs[1].secondaryButton.action();await flush();await complete(f.jobs[0]);
  assert.equal(b.scripts.length,2);assert.ok(b.scripts[1].includes('saved'));b.session.close();
});

test('VK skips queued old-page confirmations and accepts the new page',async()=>{
  const f=fixture();f.holdDialogs();const b=bridge(f);
  b.send('old-first');b.send('old-second');await flush();
  assert.equal(b.scripts.length,0);
  b.session.beginDocument('https://vk.ru/app2');b.send('new');
  f.dialogs[0].secondaryButton.action();await flush();
  assert.equal(f.jobs.length,0);assert.equal(f.dialogs.length,2);assert.equal(b.scripts.length,0);
  f.dialogs[1].secondaryButton.action();await flush();await complete(f.jobs[0]);
  assert.equal(b.scripts.length,1);assert.ok(b.scripts[0].includes('new'));b.session.close();
});

test('VK sends success only after completion and failure only after abort',async()=>{
  for(const success of [true,false]){
    const f=fixture();const b=bridge(f);b.send('request');await flush();assert.equal(b.scripts.length,0);
    const j=f.jobs[0];
    if(success) await complete(j); else {j.reject({code:2300999});await flush();}
    assert.equal(b.scripts.length,1);assert.ok(b.scripts[0].includes(success?'VKWebAppDownloadFileResult':'VKWebAppDownloadFileFailed'));
    assert.ok(b.scripts[0].includes('request'));b.session.close();
  }
});

test('VK drops old-page completion while transfer finishes and allows next-page download',async()=>{
  const f=fixture();const b=bridge(f);b.send('old');await flush();
  b.session.beginDocument('https://vk.ru/app2');await complete(f.jobs[0]);assert.equal(b.scripts.length,0);
  b.send('new');await flush();await complete(f.jobs[1]);assert.equal(b.scripts.length,1);b.session.close();
});

test('VK close before completion suppresses reply without cancelling transfer',async()=>{
  const f=fixture();const b=bridge(f);b.send('closing');await flush();b.session.close();
  await complete(f.jobs[0]);assert.equal(b.scripts.length,0);assert.ok(f.files.has('/Download/app/a.zip'));
});

test('HTTP synchronous rejection cleans file and preserves platform mapping',async()=>{
  const f=fixture();f.rejectRequest({code:401});
  await assert.rejects(f.tools.start(params.url,'nested/a.zip'),e=>e.code==='INVALID_ARGUMENT');
  assert.equal(f.jobs[0].destroyed,1);assert.equal(f.files.size,0);
  assert.equal(f.calls.find(c=>c[0]==='open')[1],'/Download/app/nested/a.zip');
});

test('progress logs are throttled, correlated and omit unknown totals and private data',async(t)=>{
  let now=1000;t.mock.method(Date,'now',()=>now);
  const f=fixture(),logs=[];
  const {SdkLogger}=f.load('main/ets/logging/SdkLogger');
  SdkLogger.install({write(level,event,details){logs.push({event,...JSON.parse(details)});}});
  const pending=f.tools.start(params.url,params.filename);await flush();const j=f.jobs[0];
  const progress=j.callbacks.get('dataReceiveProgress');
  progress({receiveSize:10,totalSize:100});
  now=1100;progress({receiveSize:20,totalSize:100});
  now=2000;progress({receiveSize:50,totalSize:100});
  now=2100;progress({receiveSize:100,totalSize:100});
  await complete(j);await pending;progress({receiveSize:200,totalSize:100});
  const updates=logs.filter(l=>l.event.startsWith('DownloadTools.downloadProgress '));
  assert.deepEqual(updates.map(l=>l.event),[
    'DownloadTools.downloadProgress 10/100 bytes (10%)',
    'DownloadTools.downloadProgress 50/100 bytes (50%)']);
  assert.equal(new Set(logs.map(l=>l.requestId)).size,1);
  assert.equal(logs.at(-1).event,'DownloadTools.downloadCompleted 100/100 bytes (100%)');
  assert.ok(logs.every(l=>Object.keys(l).sort().join(',')==='event,requestId'));
  assert.equal(j.callbacks.size,0);
  assert.equal(JSON.stringify(logs).includes(params.url),false);
  assert.equal(JSON.stringify(logs).includes(params.filename),false);
  const next=f.tools.start(params.url,'unknown');const rejected=assert.rejects(next);await flush();
  f.jobs[1].callbacks.get('dataReceiveProgress')({receiveSize:30,totalSize:0});
  assert.equal(logs.at(-1).event,'DownloadTools.downloadProgress 30 bytes');
  f.jobs[1].reject({code:2300999});await rejected;
  assert.equal(logs.at(-1).event,'DownloadTools.downloadFailed 30 bytes');
});


test('VK rejects empty and invalid filenames before dialog with client 5',async()=>{
  const separator=String.fromCharCode(92);
  const invalid=['',null,12,'   ','../a.zip','a/../b.zip','a'+separator+'..'+separator+'b.zip','/a.zip',separator+'a.zip',
    'C:'+separator+'a.zip','a//b.zip','a/','./a.zip','a/.','a<.zip','a>.zip','a:.zip','a".zip','a|.zip','a?.zip','a*.zip',
    'a\u0000.zip','a\n.zip','a\u007f.zip','a.zip ','a.','a/ /b.zip'];
  for(const filename of invalid){
    const f=fixture();const {VkBridgeProtocol}=f.load('main/ets/vendors/vk/VkBridgeProtocol');
    await assert.rejects(f.handler.downloadFile({...params,filename}),e=>
      VkBridgeProtocol.failure('Failed','r',e).data.error_data.error_code===5);
    assert.equal(f.calls.length,0);assert.equal(f.jobs.length,0);
    await assert.rejects(f.tools.start(params.url,filename));assert.equal(f.dirs.size,0);
  }
});

test('HTTP preserves requested folders and numbers only the final filename',async()=>{
  const f=fixture();f.dirs.add('/Download/app/reports');f.files.add('/Download/app/reports/2026/a.zip');
  const pending=f.tools.start(params.url,'reports/2026/a.zip');await flush();
  assert.ok(f.dirs.has('/Download/app/reports/2026'));
  assert.equal(f.calls.find(c=>c[0]==='open')[1],'/Download/app/reports/2026/a (1).zip');
  await complete(f.jobs[0]);await pending;
});

test('HTTP supports backslash folders, unicode, embedded spaces and literal dots',async()=>{
  const f=fixture();const pending=f.tools.start(params.url,'reports'+String.fromCharCode(92)+'2026/report.. final.zip');await flush();
  assert.equal(f.calls.find(c=>c[0]==='open')[1],'/Download/app/reports/2026/report.. final.zip');
  await complete(f.jobs[0]);await pending;
  const {DownloadFileName}=f.load('main/ets/utils/DownloadFileName');
  assert.deepEqual(DownloadFileName.segments('\u6587\u6863/\u56fe\u7247.zip'),['\u6587\u6863','\u56fe\u7247.zip']);
});

test('HTTP rejects parent path occupied by file before starting network',async()=>{
  const f=fixture();f.files.add('/Download/app/reports');
  await assert.rejects(f.tools.start(params.url,'reports/a.zip'));
  assert.equal(f.jobs.length,0);assert.ok(f.files.has('/Download/app/reports'));
});
