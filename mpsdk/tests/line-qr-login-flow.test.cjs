const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function str(value) { const bytes = Array.from(Buffer.from(value)); return [bytes.length, ...bytes]; }
function reply(method, sequence, fields) {
  return new Uint8Array([0x82, 0x41, sequence, ...str(method), ...fields]);
}
function loginReply(sequence) {
  return reply('qrCodeLoginV2ForSecure', sequence, [0x0c, 0,
    0x18, ...str('certificate'), 0x2c,
      0x18, ...str('v3-access'), 0x18, ...str('v3-refresh'), 0x16, 0xd0, 0x0f,
      0x1c, 0, 0x18, ...str('login-session'), 0,
    0x18, ...str('user-mid'), 0x6b, 0, 0, 0]);
}

test('fresh QR login follows APK RPC order and publishes V3 identity only after PIN confirmation', async () => {
  const { LineQrLoginClient } = createLoader()('main/ets/vendors/line/auth/LineQrLoginClient');
  const calls = [];
  const events = [];
  const transport = {
    async send(request) {
      calls.push({ method: request.method, path: request.path, sessionAccess: request.sessionAccess,
        timeoutMs: request.timeoutMs });
      const sequence = calls.length;
      switch (request.method) {
        case 'createSession': return reply(request.method, sequence, [0x0c, 0, 0x18, ...str('session-1'), 0, 0]);
        case 'createQrCodeForSecure': return reply(request.method, sequence,
          [0x0c, 0, 0x18, ...str('https://line.example/qr'), 0x15, 2, 0x15, 4,
            0x18, ...str('nonce'), 0, 0]);
        case 'checkQrCodeVerified': return reply(request.method, sequence, [0x0c, 0, 0, 0]);
        case 'verifyCertificate': return reply(request.method, sequence, [0x1c, 0x15, 4, 0, 0]);
        case 'createPinCode': return reply(request.method, sequence,
          [0x0c, 0, 0x18, ...str('123456'), 0, 0]);
        case 'checkPinCodeVerified': return reply(request.method, sequence, [0x0c, 0, 0, 0]);
        case 'qrCodeLoginV2ForSecure': return loginReply(sequence);
        default: throw new Error('unexpected method');
      }
    }
  };
  const publicKey = Uint8Array.from({ length: 32 }, (_, index) => index + 1);
  const privateKey = new Uint8Array(32).fill(7);
  const client = new LineQrLoginClient(transport, {
    create: async () => ({ publicKey, privateKey })
  });
  const credential = await client.login('device', 'model', event => events.push(event));
  assert.deepEqual(calls.map(call => call.method), [
    'createSession', 'createQrCodeForSecure', 'checkQrCodeVerified', 'verifyCertificate',
    'createPinCode', 'checkPinCodeVerified', 'qrCodeLoginV2ForSecure'
  ]);
  assert.deepEqual(calls.map(call => call.path), [
    '/acct/lgn/sq/v1', '/acct/lgn/sq/v1', '/acct/lp/lgn/sq/v1',
    '/acct/lgn/sq/v1', '/acct/lgn/sq/v1', '/acct/lp/lgn/sq/v1', '/acct/lgn/sq/v1'
  ]);
  assert.equal(calls[2].sessionAccess, 'session-1');
  assert.equal(calls[5].sessionAccess, 'session-1');
  assert.ok(calls[2].timeoutMs > 0 && calls[2].timeoutMs <= 2000);
  assert.equal(events[0].kind, 'qrReady');
  assert.equal(events[0].url, 'https://line.example/qr?secret=' +
    encodeURIComponent(Buffer.from(publicKey).toString('base64')) + '&e2eeVersion=1');
  assert.equal(events[1].kind, 'qrVerified');
  assert.equal(events[2].kind, 'pinReady');
  assert.equal(events[2].pin, '123456');
  assert.equal(events[3].kind, 'authorized');
  assert.equal(events[3].mid, 'user-mid');
  assert.equal(credential.accessToken, 'v3-access');
  assert.ok(privateKey.every(byte => byte === 0));
});

test('QR cancellation while obtaining keys clears the unused private-key copy', async () => {
  const { LineQrLoginClient } = createLoader()('main/ets/vendors/line/auth/LineQrLoginClient');
  let finishKeys;
  const privateKey = new Uint8Array(32).fill(9);
  const client = new LineQrLoginClient({ send: async request => {
    if (request.method === 'createSession') {
      return reply('createSession', 1, [0x0c, 0, 0x18, ...str('session-1'), 0, 0]);
    }
    throw new Error('unexpected request');
  } }, { create: () => new Promise(resolve => { finishKeys = resolve; }) });
  const pending = client.login('device', 'model', () => {});
  while (!finishKeys) await new Promise(resolve => setImmediate(resolve));
  client.cancel();
  finishKeys({ publicKey: new Uint8Array(32), privateKey });
  await assert.rejects(pending, error => error.code === 'LINE_LOGIN_CANCELLED');
  assert.ok(privateKey.every(byte => byte === 0));
});

test('QR deadline expires a pending poll without renewing or accepting a late success', async t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: 100000 });
  const { LineQrLoginClient } = createLoader()('main/ets/vendors/line/auth/LineQrLoginClient');
  const methods = [];
  let finishPoll;
  const events = [];
  const client = new LineQrLoginClient({ send: async request => {
    methods.push(request.method);
    const sequence = methods.length;
    if (request.method === 'createSession') return reply(request.method, sequence,
      [0x0c, 0, 0x18, ...str('session-1'), 0, 0]);
    if (request.method === 'createQrCodeForSecure') return reply(request.method, sequence,
      [0x0c, 0, 0x18, ...str('https://line.example/qr'), 0x15, 4, 0x15, 6,
        0x18, ...str('nonce'), 0, 0]); // two polls, three seconds each
    if (request.method === 'checkQrCodeVerified') return new Promise(resolve => { finishPoll = resolve; });
    assert.fail('expired QR must not proceed to certificate verification');
  } }, { create: async () => ({ publicKey: new Uint8Array(32), privateKey: new Uint8Array(32) }) });
  const pending = client.login('device', 'model', event => events.push(event));
  const rejected = assert.rejects(pending, error => error.code === 'LINE_QR_CONFIRM_TIMEOUT');
  while (!finishPoll) await new Promise(resolve => setImmediate(resolve));
  t.mock.timers.tick(6000);
  await rejected;
  finishPoll(reply('checkQrCodeVerified', 3, [0x0c, 0, 0, 0]));
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(methods, ['createSession', 'createQrCodeForSecure', 'checkQrCodeVerified']);
  assert.deepEqual(events.map(event => event.kind), ['qrReady']);
});

test('zero poll interval uses the default budget and cancellation settles without a network reply', async t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: 100000 });
  const { LineQrLoginClient } = createLoader()('main/ets/vendors/line/auth/LineQrLoginClient');
  const events = [];
  let polling = false;
  const client = new LineQrLoginClient({ send: async request => {
    if (request.method === 'createSession') return reply(request.method, 1,
      [0x0c, 0, 0x18, ...str('session'), 0, 0]);
    if (request.method === 'createQrCodeForSecure') return reply(request.method, 2,
      [0x0c, 0, 0x18, ...str('https://line.example/qr'), 0x15, 4, 0x15, 0,
        0x18, ...str('nonce'), 0, 0]);
    polling = true;
    return new Promise(() => {});
  } }, { create: async () => ({ publicKey: new Uint8Array(32), privateKey: new Uint8Array(32) }) });
  const pending = client.login('device', 'model', event => events.push(event));
  const rejected = assert.rejects(pending, error => error.code === 'LINE_LOGIN_CANCELLED');
  while (!polling) await new Promise(resolve => setImmediate(resolve));
  t.mock.timers.tick(30000);
  assert.equal(events.length, 1); // UI refresh countdown must not expire the login session.
  client.cancel();
  await rejected;
  t.mock.timers.tick(240000);
  assert.equal(events.length, 1);
});

test('QR confirmation clears its deadline while PIN confirmation is still pending', async t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: 100000 });
  const { LineQrLoginClient } = createLoader()('main/ets/vendors/line/auth/LineQrLoginClient');
  const events = [];
  let finishPin;
  let sequence = 0;
  const client = new LineQrLoginClient({ send: async request => {
    sequence++;
    switch (request.method) {
      case 'createSession': return reply(request.method, sequence, [0x0c, 0, 0x18, ...str('session'), 0, 0]);
      case 'createQrCodeForSecure': return reply(request.method, sequence,
        [0x0c, 0, 0x18, ...str('https://line.example/qr'), 0x15, 2, 0x15, 4,
          0x18, ...str('nonce'), 0, 0]);
      case 'checkQrCodeVerified': return reply(request.method, sequence, [0x0c, 0, 0, 0]);
      case 'verifyCertificate': return reply(request.method, sequence, [0x1c, 0x15, 4, 0, 0]);
      case 'createPinCode': return reply(request.method, sequence, [0x0c, 0, 0x18, ...str('123456'), 0, 0]);
      case 'checkPinCodeVerified': return new Promise(resolve => {
        const pinSequence = sequence;
        finishPin = () => resolve(reply(request.method, pinSequence, [0x0c, 0, 0, 0]));
      });
      case 'qrCodeLoginV2ForSecure': return loginReply(sequence);
      default: assert.fail('unexpected request');
    }
  } }, { create: async () => ({ publicKey: new Uint8Array(32), privateKey: new Uint8Array(32) }) });
  const pending = client.login('device', 'model', event => events.push(event));
  while (!finishPin) await new Promise(resolve => setImmediate(resolve));
  assert.equal(events.at(-1).kind, 'pinReady');
  t.mock.timers.tick(20000);
  finishPin();
  assert.equal((await pending).mid, 'user-mid');
  assert.equal(events.at(-1).kind, 'authorized');
});

test('cancelling a pending QR poll discards its late success', async () => {
  const { LineQrLoginClient } = createLoader()('main/ets/vendors/line/auth/LineQrLoginClient');
  let finishPoll;
  const methods = [];
  const events = [];
  const transport = {
    async send(request) {
      methods.push(request.method);
      const sequence = methods.length;
      if (request.method === 'createSession') return reply(request.method, sequence,
        [0x0c, 0, 0x18, ...str('session-1'), 0, 0]);
      if (request.method === 'createQrCodeForSecure') return reply(request.method, sequence,
        [0x0c, 0, 0x18, ...str('https://line.example/qr'), 0x15, 2, 0x15, 4,
          0x18, ...str('nonce'), 0, 0]);
      if (request.method === 'checkQrCodeVerified') return new Promise(resolve => { finishPoll = resolve; });
      throw new Error('unexpected request after cancellation');
    }
  };
  const client = new LineQrLoginClient(transport, {
    create: async () => ({ publicKey: new Uint8Array(32), privateKey: new Uint8Array(32) })
  });
  const pending = client.login('device', 'model', event => events.push(event));
  while (!finishPoll) await new Promise(resolve => setImmediate(resolve));
  client.cancel();
  finishPoll(reply('checkQrCodeVerified', 3, [0x0c, 0, 0, 0]));
  await assert.rejects(pending, error => error.code === 'LINE_LOGIN_CANCELLED');
  assert.deepEqual(methods, ['createSession', 'createQrCodeForSecure', 'checkQrCodeVerified']);
  assert.equal(events.some(event => event.kind === 'authorized'), false);
});

test('unexpected platform error after QR confirmation identifies the failed login stage', async () => {
  const load = createLoader();
  const { LineQrLoginClient } = load('main/ets/vendors/line/auth/LineQrLoginClient');
  const { SdkLogger } = load('main/ets/logging/SdkLogger');
  const logs = [];
  SdkLogger.install({ write(_level, event, details) { logs.push({ event, details: JSON.parse(details) }); } });
  const transport = {
    async send(request) {
      const method = request.method;
      const sequence = method === 'createSession' ? 1 : method === 'createQrCodeForSecure' ? 2 :
        method === 'checkQrCodeVerified' ? 3 : 4;
      if (method === 'createSession') return reply(method, sequence,
        [0x0c, 0, 0x18, ...str('session-1'), 0, 0]);
      if (method === 'createQrCodeForSecure') return reply(method, sequence,
        [0x0c, 0, 0x18, ...str('https://line.example/qr'), 0x15, 2, 0x15, 4,
          0x18, ...str('nonce'), 0, 0]);
      if (method === 'checkQrCodeVerified') return reply(method, sequence, [0x0c, 0, 0, 0]);
      throw new Error('private transport detail');
    }
  };
  const client = new LineQrLoginClient(transport, {
    create: async () => ({ publicKey: new Uint8Array(32), privateKey: new Uint8Array(32) })
  });
  await assert.rejects(client.login('device', 'model', () => {}),
    error => error.code === 'LINE_LOGIN_FAILED_VERIFY_CERTIFICATE_SEND');
  assert.equal(logs.at(-1)?.event, 'LineQrLogin.verifyCertificateSendFailed');
  assert.equal(logs.at(-1)?.details.code, 'Error');
  assert.equal(JSON.stringify(logs).includes('private transport detail'), false);
});
