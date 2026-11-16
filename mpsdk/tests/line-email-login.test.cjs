const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

const str = value => [Buffer.byteLength(value), ...Buffer.from(value)];
const field = (id, type, value) => [type, id * 2, ...value];
const struct = (...fields) => [...fields.flat(), 0];
function reply(request, fields) {
  return Uint8Array.from([0x82, 0x41, request.body[2], ...str(request.method), ...fields]);
}
const rsa = () => struct(field(1, 8, str('key')), field(2, 8, str('abcd')),
  field(3, 8, str('010001')), field(4, 8, str('session')));
const token = () => struct(field(1, 8, str('access')), field(2, 8, str('refresh')),
  field(3, 6, [0xd8, 4]), field(5, 8, str('login-session')));
const success = () => struct(field(5, 5, [2]), field(9, 12, token()), field(10, 8, str('mid')));
const waiting = () => struct(field(3, 8, str('pending-verifier')), field(5, 5, [6]));
const json = value => new TextEncoder().encode(JSON.stringify(value));

function setup(loginReplies, verification, cryptoOverrides = {}, platformOverrides = {}) {
  const load = createLoader({}, {}, undefined, {}, undefined, undefined, {
    '@kit.ArkTS': { util: {
      TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
      TextDecoder: { create: (enc, options) => ({ decodeToString: value => new TextDecoder(enc, options).decode(value) }) },
      Base64Helper: class { decodeSync(value) { return new Uint8Array(Buffer.from(value, 'base64')); } }
    } }, ...platformOverrides
  });
  const requests = [];
  const pair = { publicKey: new Uint8Array(32).fill(1), privateKey: new Uint8Array(32).fill(2), secret: new Uint8Array(32).fill(3) };
  const crypto = { createPin: () => '012345', createE2ee: async () => pair,
    createIdentity: async (_key, email, password) => {
      assert.equal(email, 'a@example.com'); assert.equal(password, ' secret '); return 'aabb';
    }, confirmE2ee: async () => new Uint8Array(16).fill(8), ...cryptoOverrides };
  let loginIndex = 0;
  const transport = { send: async request => {
    requests.push(request);
    if (request.method === 'getRSAKeyInfo') return reply(request, struct(field(0, 12, rsa())));
    if (request.method === 'loginV2') {
      const value = loginReplies[loginIndex++];
      return typeof value === 'function' ? value(request) : reply(request, struct(field(0, 12, value)));
    }
    if (request.method === 'verifyEmailPin') return typeof verification === 'function' ? verification() : json(verification);
    if (request.method === 'confirmE2EELogin') return reply(request, struct(field(0, 8, str('confirmed-verifier'))));
    assert.fail('unexpected method ' + request.method);
  } };
  const { LineEmailLoginClient } = load('main/ets/vendors/line/auth/LineEmailLoginClient');
  return { client: new LineEmailLoginClient(transport, crypto), requests, pair, transport, load };
}

function loginFields(h, request) {
  const { LineCompactReader } = h.load('main/ets/vendors/line/network/LineCompactCodec');
  const reader = new LineCompactReader(request.body);
  reader.byte(); reader.byte(); reader.uint(); reader.string();
  const values = new Map();
  reader.struct((id, type) => {
    if (id !== 2 || type !== 12) return false;
    reader.struct((key, kind) => {
      if (kind === 5) values.set(key, reader.integer());
      else if (kind === 8) values.set(key, reader.take(reader.uint()));
      else return false;
      return true;
    });
    return true;
  });
  return values;
}

test('email direct success does not show PIN or enter verification', async () => {
  const h = setup([success()]);
  const events = [];
  const result = await h.client.login('a@example.com', ' secret ', 'device', 'model', state => events.push(state));
  assert.equal(result.mid, 'mid');
  assert.deepEqual(h.requests.map(r => r.method), ['getRSAKeyInfo', 'loginV2']);
  assert.deepEqual(events.map(s => s.kind), ['authenticating']);
  assert.ok(h.pair.privateKey.every(x => x === 0));
});

test('email RPC debug logs retain raw request and rejected response only in private HiLog details', async () => {
  const calls = [];
  const h = setup([request => reply(request, struct(field(1, 12, struct(field(1, 5, [70])))))], undefined, {},
    { '@kit.PerformanceAnalysisKit': { hilog: {
      debug: (...args) => calls.push(args), info() {}, warn() {}, error() {}
    } } });
  const { SdkLogger, SdkLogLevel } = h.load('main/ets/logging/SdkLogger');
  const { HiLogSink } = h.load('main/ets/logging/HiLogSink');
  SdkLogger.install(new HiLogSink());
  SdkLogger.setLevel(SdkLogLevel.DEBUG);
  await assert.rejects(h.client.login('a@example.com', ' secret ', 'device', 'model', () => {}),
    error => error.code === 'LINE_EMAIL_SERVICE_ERROR_35');
  const request = calls.find(args => args[3] === 'LineEmailLogin.loginV2Request');
  const response = calls.find(args => args[3] === 'LineEmailLogin.loginV2Response');
  assert.equal(request[2], '%{public}s %{private}s');
  assert.equal(response[2], '%{public}s %{private}s');
  assert.deepEqual(JSON.parse(JSON.parse(request[4]).data), [...h.requests[1].body]);
  assert.deepEqual(JSON.parse(JSON.parse(response[4]).data), [...reply(h.requests[1],
    struct(field(1, 12, struct(field(1, 5, [70])))))]);
  const regular = [];
  SdkLogger.install({ write(_level, _event, details) { regular.push(JSON.parse(details)); } });
  SdkLogger.info('test', 'info', { data: 'private payload' });
  assert.equal(regular[0].data, undefined);
  SdkLogger.setLevel(SdkLogLevel.INFO);
  SdkLogger.debug('test', 'debug', { data: 'private payload' });
  assert.equal(regular.length, 1);
});

test('email E2EE verification computes proof then confirms and logs in with returned verifier', async () => {
  let proofs = 0;
  const h = setup([waiting(), success()], { authPhase: 'PIN_CODE_DELIVERED', result: { metadata: {
    errorCode: 'SUCCESS', publicKey: Buffer.alloc(32, 4).toString('base64'),
    encryptedKeyChain: Buffer.alloc(16, 5).toString('base64')
  } } }, { confirmE2ee: async (privateKey, publicKey, chain) => {
    proofs++; assert.equal(privateKey[0], 2); assert.equal(publicKey[0], 4); assert.equal(chain[0], 5);
    return new Uint8Array(16).fill(8);
  } });
  const events = [];
  await h.client.login('a@example.com', ' secret ', 'device', 'model', state => events.push(state));
  assert.equal(proofs, 1);
  assert.deepEqual(h.requests.map(r => r.method), ['getRSAKeyInfo', 'loginV2', 'verifyEmailPin',
    'confirmE2EELogin', 'getRSAKeyInfo', 'loginV2']);
  assert.equal(h.requests[2].path, '/LF1');
  assert.equal(h.requests[2].sessionAccess, 'pending-verifier');
  assert.equal(events.find(s => s.kind === 'pinReady').pin, '012345');
  assert.ok(Buffer.from(h.requests.at(-1).body).includes(Buffer.from('confirmed-verifier')));
  const initial = loginFields(h, h.requests[1]);
  const final = loginFields(h, h.requests.at(-1));
  assert.equal(initial.get(1), 2);
  assert.equal(initial.has(9), false); // APK first login has null verifier, omitted on wire.
  assert.equal(final.get(1), 1); // APK continuation uses QRCODE even from email UI.
  assert.equal(Buffer.from(final.get(9)).toString(), 'confirmed-verifier');
  assert.ok(h.pair.privateKey.every(x => x === 0));
});

test('only APK E2EE sender-not-allowed retries ordinary credentials and switches verification to Q', async () => {
  const reject = code => request => reply(request, struct(field(1, 12, struct(field(1, 5,
    code < 64 ? [code * 2] : [((code * 2) & 127) | 128, (code * 2) >> 7])))));
  const h = setup([reject(89), waiting(), success()], {
    authPhase: 'QRCODE_VERIFIED', result: { verifier: 'plain-verified' }
  });
  const result = await h.client.login('a@example.com', ' secret ', 'd', 'm', () => {});
  assert.equal(result.mid, 'mid');
  const loginRequests = h.requests.filter(r => r.method === 'loginV2');
  assert.deepEqual(loginRequests.map(r => loginFields(h, r).get(1)), [2, 0, 1]);
  assert.equal(loginFields(h, loginRequests[1]).has(10), false);
  assert.equal(loginFields(h, loginRequests[1]).get(11), 0);
  assert.equal(h.requests.find(r => r.method === 'verifyEmailPin').path, '/Q');
  const other = setup([reject(8)]);
  await assert.rejects(other.client.login('a@example.com', ' secret ', 'd', 'm', () => {}),
    error => error.code === 'LINE_EMAIL_SERVICE_ERROR_8');
  assert.equal(other.requests.length, 2);
});

test('verification deadline settles once and ignores the late server reply', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let finish;
  const h = setup([waiting()], () => new Promise(resolve => { finish = resolve; }));
  const pending = h.client.login('a@example.com', ' secret ', 'd', 'm', () => {});
  while (!finish) await new Promise(resolve => setImmediate(resolve));
  const rejected = assert.rejects(pending, error => error.code === 'LINE_EMAIL_VERIFICATION_TIMEOUT');
  t.mock.timers.tick(180000);
  await rejected;
  finish(json({ authPhase: 'QRCODE_VERIFIED', result: { verifier: 'late' } }));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(h.requests.length, 3);
});

test('verification refusal and invalid E2EE never send final confirmation or publish a credential', async () => {
  const h = setup([waiting()], { authPhase: 'PIN_CODE_DELIVERED', result: { metadata: { errorCode: 'CANCEL' } } });
  await assert.rejects(h.client.login('a@example.com', ' secret ', 'd', 'm', () => {}),
    error => error.code === 'LINE_EMAIL_VERIFICATION_REJECTED');
  assert.equal(h.requests.some(r => r.method === 'confirmE2EELogin'), false);
  assert.ok(h.pair.privateKey.every(x => x === 0));
});

test('an E2EE attempt cannot skip its proof using a plain verifier response', async () => {
  const h = setup([waiting()], { authPhase: 'QRCODE_VERIFIED', result: { verifier: 'plain-only' } });
  await assert.rejects(h.client.login('a@example.com', ' secret ', 'd', 'm', () => {}),
    error => error.code === 'LINE_EMAIL_PROTOCOL_ERROR');
  assert.equal(h.requests.filter(r => r.method === 'loginV2').length, 1);
});

test('cancel settles verification immediately and discards a late verification result', async () => {
  let finish;
  const h = setup([waiting()], () => new Promise(resolve => { finish = resolve; }));
  const pending = h.client.login('a@example.com', ' secret ', 'd', 'm', () => {});
  while (!finish) await new Promise(resolve => setImmediate(resolve));
  h.client.cancel();
  await assert.rejects(pending, error => error.code === 'LINE_LOGIN_CANCELLED');
  finish(json({ authPhase: 'QRCODE_VERIFIED', result: { verifier: 'late' } }));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(h.requests.length, 3);
  assert.ok(h.pair.privateKey.every(x => x === 0));
});

test('cancellation during E2EE proof creation clears a late proof without sending it', async () => {
  let finishProof;
  const proof = new Uint8Array(16).fill(8);
  const h = setup([waiting()], { authPhase: 'PIN_CODE_DELIVERED', result: { metadata: {
    errorCode: 'SUCCESS', publicKey: Buffer.alloc(32, 4).toString('base64'),
    encryptedKeyChain: Buffer.alloc(16, 5).toString('base64')
  } } }, { confirmE2ee: () => new Promise(resolve => { finishProof = resolve; }) });
  const pending = h.client.login('a@example.com', ' secret ', 'd', 'm', () => {});
  while (!finishProof) await new Promise(resolve => setImmediate(resolve));
  h.client.cancel();
  await assert.rejects(pending, error => error.code === 'LINE_LOGIN_CANCELLED');
  finishProof(proof);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(h.requests.some(request => request.method === 'confirmE2EELogin'), false);
  assert.ok(proof.every(byte => byte === 0), 'late proof must be cleared after cancellation');
});
