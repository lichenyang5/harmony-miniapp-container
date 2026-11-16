const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const strings = require('../src/main/resources/base/element/string.json').string;
function resourceText(value) {
  if (typeof value === 'string') return value;
  const text = strings.find(s => s.name === value.name.split('.').pop()).value;
  return value.params.reduce((text, param) => text.replace('%s', String(param)), text);
}

function fixture() {
  const callbacks = new Map();
  const calls = [];
  let dialogResult = { index: 1 };
  let createError;
  let createGate;
  let windowGate;
  let pickerGate;
  let pickerError;
  let copyError;
  let collide = false;
  const task = { tid: 'task-1', config: { saveas: '/cache/a.zip' },
    on(name, cb) { callbacks.set(name, cb); }, off(name) { callbacks.delete(name); },
    async start() { calls.push('start'); } };
  const host = { cacheDir: '/cache', applicationInfo: { accessTokenId: 1 } };
  const load = createLoader({}, {}, {}, {}, () => true, { DEBUG: false }, {
    '@kit.BasicServicesKit': { deviceInfo: { sdkApiVersion: 15 }, request: { agent: {
      Action: { DOWNLOAD: 0 }, Mode: { BACKGROUND: 1 },
      async create(context, config) { calls.push(config); if (createError) throw createError;
        if (createGate) await createGate; return task; },
      async remove(id) { calls.push(['remove', id]); }
    } } },
    '@kit.ArkUI': { window: { async getLastWindow() { if (windowGate) await windowGate; return { getUIContext() { return {
      showAlertDialog(options) {
        calls.push(options);
        if (dialogResult.index === 1) options.secondaryButton.action();
        else options.primaryButton.action();
      }
    }; } }; } } },
    '@kit.CoreFileKit': {
      picker: { DocumentPickerMode: { DOWNLOAD: 1 }, DocumentSaveOptions: class {},
        DocumentViewPicker: class { async save() { if (pickerError) throw pickerError; if (pickerGate) await pickerGate; return ['file://docs/Download/app']; } } },
      fileUri: { FileUri: class { constructor(value) { this.path = value.replace('file://docs', ''); this.name = value.split('/').pop(); } } },
      fileIo: { OpenMode: { READ_WRITE: 2, CREATE: 64 },
        mkdirSync(path) { calls.push(['mkdir', path]); if (collide) { collide = false; throw {code:13900015}; } },
        accessSync() { return false; }, openSync(path) { calls.push(['open', path]); return { fd: 3 }; },
        closeSync() { calls.push('close'); }, async copyFile(source, fd) {
          calls.push(['copy', source, fd]); if (copyError) throw copyError; },
        async unlink(path) { calls.push(['unlink', path]); }
      }
    }
  });
  const { AgentDownloadTools } = load('main/ets/capabilities/files/AgentDownloadTools');
  const tools = new AgentDownloadTools(host);
  return { load, host, tools, task, calls, callbacks,
    setDialog(value) { dialogResult = value; }, setError(value) { createError = value; },
    deferCreate(value) { createGate = value; }, deferWindow(value) { windowGate = value; },
    deferPicker(value) { pickerGate = value; }, setPickerError(value) { pickerError = value; }, setCopyError(value) { copyError = value; },
    collide() { collide = true; } };
}

test('system receives raw parameters and accepted start precedes public copy', async () => {
  const f = fixture();
  await f.tools.start('https://example.test/a.zip', 'a.zip');
  const config = f.calls.find(c => c && c.url);
  assert.equal(config.url, 'https://example.test/a.zip');
  assert.equal(config.saveas, 'a.zip');
  assert.equal(config.overwrite, true);
  assert.ok(f.calls.includes('start'));
  assert.equal(f.calls.some(c => Array.isArray(c) && c[0] === 'copy'), false);
  await f.callbacks.get('completed')({});
  await new Promise(resolve => setImmediate(resolve));
  assert.ok(f.calls.some(c => Array.isArray(c) && c[0] === 'copy'));
  assert.ok(f.calls.some(c => Array.isArray(c) && c[0] === 'remove'));
});

test('invalid business fields reach the system without SDK validation', async () => {
  const f = fixture(); f.setError({ code: 401 });
  await assert.rejects(f.tools.start(12, null));
  const config = f.calls.find(c => c && c.url === 12);
  assert.equal(config.saveas, null);
});

test('stale request removes prepared task without starting it', async () => {
  const f = fixture();
  let resolve;
  f.deferCreate(new Promise(r => { resolve = r; }));
  const pending = f.tools.start('https://example.test/a', 'a.zip');
  await new Promise(resolve => setImmediate(resolve));
  assert.ok(f.calls.some(c => c && c.url));
  f.tools.dispose(); resolve();
  await assert.rejects(pending);
  assert.equal(f.calls.includes('start'), false);
  assert.ok(f.calls.some(c => Array.isArray(c) && c[0] === 'remove'));
});

test('page invalidation during public directory lookup prevents system task creation', async () => {
  const f = fixture(); let resolve;
  f.deferPicker(new Promise(r => { resolve = r; }));
  const pending = f.tools.start('https://example.test/a', 'a.zip');
  f.tools.dispose(); resolve(); await assert.rejects(pending);
  assert.equal(f.calls.some(c => c && c.url), false);
});

test('task failure and duplicate terminal notifications clean once without public copy', async () => {
  const f = fixture(); await f.tools.start('https://example.test/a', 'a.zip');
  const fail = f.callbacks.get('failed'); const complete = f.callbacks.get('completed');
  fail({}); complete({}); await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.calls.filter(c => Array.isArray(c) && c[0] === 'remove').length, 1);
  assert.equal(f.calls.some(c => Array.isArray(c) && c[0] === 'copy'), false);
  assert.equal(f.callbacks.size, 0);
});

test('failed start removes task and suppresses an early completion notification', async () => {
  const f = fixture();
  f.task.start = async () => { f.callbacks.get('completed')({}); throw {code:21900004}; };
  await assert.rejects(f.tools.start('https://example.test/a', 'a.zip'));
  assert.equal(f.calls.some(c => Array.isArray(c) && c[0] === 'copy'), false);
  assert.ok(f.calls.some(c => Array.isArray(c) && c[0] === 'remove'));
});

test('public directory collisions retry exclusively and copy failure cleans only the owned file', async () => {
  const f = fixture(); f.collide(); f.setCopyError({code:13900005});
  await f.tools.start('https://example.test/a', 'a.zip');
  f.callbacks.get('completed')({}); await new Promise(resolve => setImmediate(resolve));
  const directories = f.calls.filter(c => Array.isArray(c) && c[0] === 'mkdir').map(c => c[1]);
  assert.deepEqual(directories, ['/Download/app/download-task-1', '/Download/app/download-task-1-1']);
  assert.ok(f.calls.includes('close'));
  assert.ok(f.calls.some(c => Array.isArray(c) && c[0] === 'unlink' && c[1] === directories[1] + '/a.zip'));
  assert.equal(f.calls.some(c => Array.isArray(c) && c[0] === 'unlink' && c[1].startsWith(directories[0] + '/')), false);
});
