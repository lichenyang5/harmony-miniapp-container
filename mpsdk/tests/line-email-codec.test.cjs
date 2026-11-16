const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function codec() {
  return createLoader({}, {}, undefined, undefined, undefined, undefined, {
    '@kit.ArkTS': { util: {
      TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
      TextDecoder: { create: (encoding, options) => ({ decodeToString: bytes => new TextDecoder(encoding, options).decode(bytes) }) },
      Base64Helper: class { decodeSync(value) { return new Uint8Array(Buffer.from(value, 'base64')); } }
    } }
  })('main/ets/vendors/line/auth/LineEmailLoginCodec').LineEmailLoginCodec;
}

const str = value => [Buffer.byteLength(value), ...Buffer.from(value)];
const field = (id, type, bytes) => [type, id * 2, ...bytes];
const struct = (...fields) => [...fields.flat(), 0];
const reply = (method, body, sequence = 1) => Uint8Array.from([0x82, 0x41, sequence, ...str(method), ...body]);
const ok = value => struct(field(0, 12, value));
const rsa = () => struct(field(1, 8, str('key')), field(2, 8, str('abcd')), field(3, 8, str('010001')),
  field(4, 8, str('session')), field(20, 9, [0x12, 1]));
const token = () => struct(field(1, 8, str('access')), field(2, 8, str('refresh')),
  field(3, 6, [0xd8, 4]), field(5, 8, str('login-session')));

test('email login Compact request preserves wire fields, true BOOL and binary secret', () => {
  const c = codec();
  assert.deepEqual([...c.encodeLogin({ type: 2, keynm: 'k', password: 'abcd', systemName: 's', modelName: 'm',
    verifier: '', e2eeVersion: 1, secret: new Uint8Array([0, 255]) }, 1)],
  [0x82, 0x21, 1, ...str('loginV2'), 0x2c, 0x15, 4, 0x15, 2, 0x18, ...str('k'), 0x18,
    ...str('abcd'), 0x11, 0x28, ...str('s'), 0x18, 0, 0x18, 0, 0x18, 2, 0, 255, 0x15, 2, 0x18, ...str('m'), 0, 0]);
  // gp8/s0 与 gp8/kl 的参数编号均为 2，不能套用扫码服务的 REQUEST=1。
  assert.deepEqual([...c.encodeRsaKey(1)], [0x82, 0x21, 1, ...str('getRSAKeyInfo'), 0x25, 2, 0]);
  assert.deepEqual([...c.encodeConfirm('v', new Uint8Array([0, 255]), 1)],
    [0x82, 0x21, 1, ...str('confirmE2EELogin'), 0x18, 1, 118, 0x18, 2, 0, 255, 0]);
});

test('RSA and email login responses preserve V3 credentials and skip unknown fields', () => {
  const c = codec();
  assert.deepEqual(c.decodeRsaKey(reply('getRSAKeyInfo', ok(rsa())), 1),
    { keynm: 'key', nvalue: 'abcd', evalue: '010001', sessionKey: 'session' });
  const result = c.decodeLogin(reply('loginV2', ok(struct(field(2, 8, str('')), field(5, 5, [2]),
    field(9, 12, token()), field(10, 8, str('mid'))))), 1);
  assert.equal(result.type, 1);
  assert.equal(result.credential.mid, 'mid');
  assert.equal(result.credential.certificate, '');
  assert.equal(result.credential.accessToken, 'access');
  assert.equal(result.credential.durationUntilRefreshInSec, 300);
  assert.deepEqual([...result.credential.metaData], []);
  const pending = c.decodeLogin(reply('loginV2', ok(struct(field(3, 8, str('v')), field(4, 8, str('123456')),
    field(5, 5, [6])))), 1);
  assert.equal(pending.type, 3);
  assert.equal(pending.verifier, 'v');
  assert.equal(pending.pin, '123456');
  assert.equal(c.decodeConfirm(reply('confirmE2EELogin', struct(field(0, 8, str('verified')))), 1), 'verified');
});

test('email service errors retain private reason only in originalCause after complete envelope validation', () => {
  const c = codec();
  const failure = reply('loginV2', struct(field(1, 12, struct(field(1, 5, [40]), field(2, 8, str('private reason'))))));
  assert.throws(() => c.decodeLogin(failure, 1), error => error.code === 'LINE_EMAIL_SERVICE_ERROR_20' &&
    error.message !== 'private reason' && error.originalCause.message === 'private reason');
  for (const bytes of [failure.slice(0, -1), Uint8Array.from([...failure, 0]),
    reply('loginV2', struct(field(0, 12, struct()), field(1, 12, struct(field(1, 5, [40])))))]) {
    assert.throws(() => c.decodeLogin(bytes, 1), error => error.code === 'LINE_EMAIL_PROTOCOL_ERROR');
  }
});

test('email replies reject mismatched, missing, duplicate and incomplete success results', () => {
  const c = codec();
  for (const bytes of [reply('getRSAKeyInfo', ok(rsa()), 2), reply('other', ok(rsa())),
    reply('getRSAKeyInfo', ok(struct())), reply('getRSAKeyInfo', struct(field(0, 12, rsa()), field(0, 12, rsa()))),
    reply('getRSAKeyInfo', struct())]) {
    assert.throws(() => c.decodeRsaKey(bytes, 1), error => error.code === 'LINE_EMAIL_PROTOCOL_ERROR');
  }
  assert.throws(() => c.decodeLogin(reply('loginV2', ok(struct(field(5, 5, [2])))), 1),
    error => error.code === 'LINE_EMAIL_PROTOCOL_ERROR');
  assert.throws(() => c.encodeLogin({ type: 2, keynm: 'k', password: 'plain password', systemName: 's', modelName: 'm', e2eeVersion: 1 }, 1));
});

test('application exceptions keep private diagnostics only after validating the full message', () => {
  const c = codec();
  const exception = Uint8Array.from([0x82, 0x61, 1, ...str('loginV2'),
    ...struct(field(1, 8, str('private application exception')), field(2, 5, [12]))]);
  assert.throws(() => c.decodeLogin(exception, 1), error => error.code === 'LINE_EMAIL_APPLICATION_ERROR' &&
    error.originalCause.message === 'private application exception' && !error.message.includes('private'));
  assert.throws(() => c.decodeLogin(exception.slice(0, -1), 1), error => error.code === 'LINE_EMAIL_PROTOCOL_ERROR');
  assert.throws(() => c.decodeLogin(Uint8Array.from([...exception, 0]), 1), error => error.code === 'LINE_EMAIL_PROTOCOL_ERROR');
  const duplicate = Uint8Array.from([0x82, 0x61, 1, ...str('loginV2'),
    ...struct(field(1, 8, str('first')), field(1, 8, str('second')))]);
  assert.throws(() => c.decodeLogin(duplicate, 1), error => error.code === 'LINE_EMAIL_PROTOCOL_ERROR');
});

test('duplicate V3 token structs or credential fields never silently overwrite identity', () => {
  const c = codec();
  const duplicateToken = struct(field(1, 8, str('first')), field(1, 8, str('replacement')),
    field(2, 8, str('refresh')), field(3, 6, [0xd8, 4]), field(5, 8, str('session')));
  for (const content of [struct(field(5, 5, [2]), field(9, 12, token()), field(9, 12, token()), field(10, 8, str('mid'))),
    struct(field(5, 5, [2]), field(9, 12, duplicateToken), field(10, 8, str('mid')))]) {
    assert.throws(() => c.decodeLogin(reply('loginV2', ok(content)), 1), error => error.code === 'LINE_EMAIL_PROTOCOL_ERROR');
  }
});

test('QR and SMS confirmation result types retain the verifier without fabricating credentials', () => {
  const c = codec();
  for (const type of [2, 4]) {
    const result = c.decodeLogin(reply('loginV2', ok(struct(field(3, 8, str('pending')), field(5, 5, [type * 2])))), 1);
    assert.equal(result.type, type);
    assert.equal(result.verifier, 'pending');
    assert.equal(result.credential, undefined);
  }
});

test('verification JSON accepts top-level or nested phases and decodes E2EE bytes', () => {
  const c = codec();
  const json = value => new TextEncoder().encode(JSON.stringify(value));
  assert.deepEqual(c.decodeVerification(json({ authPhase: 'QRCODE_VERIFIED', result: { verifier: 'v' } })),
    { kind: 'verifier', verifier: 'v' });
  assert.deepEqual(c.decodeVerification(json({ result: { authPhase: 'QRCODE_VERIFIED', verifier: 'nested' } })),
    { kind: 'verifier', verifier: 'nested' });
  const publicKey = Buffer.alloc(32, 7);
  const encryptedKeyChain = Buffer.alloc(16, 9);
  const parsed = c.decodeVerification(json({ authPhase: 'PIN_CODE_DELIVERED', result: { metadata: {
    errorCode: 'SUCCESS', publicKey: publicKey.toString('base64'), encryptedKeyChain: encryptedKeyChain.toString('base64')
  } } }));
  assert.equal(parsed.kind, 'e2ee');
  assert.deepEqual([...parsed.publicKey], [...publicKey]);
  assert.deepEqual([...parsed.encryptedKeyChain], [...encryptedKeyChain]);
  assert.deepEqual(c.decodeVerification(json({ authPhase: 'PIN_CODE_DELIVERED', result: { metadata: { errorCode: 'CANCEL' } } })),
    { kind: 'cancel' });
});

test('verification JSON rejects malformed types, phases and invalid Base64 without exposing payload', () => {
  const c = codec();
  for (const raw of ['{bad', 'null', '{}', '{"result":[],"authPhase":"QRCODE_VERIFIED"}',
    '{"result":{"verifier":""},"authPhase":"QRCODE_VERIFIED"}',
    '{"result":{},"authPhase":"UNKNOWN"}',
    '{"result":{"metadata":{"errorCode":"SUCCESS","publicKey":"%%%","encryptedKeyChain":"abcd"}},"authPhase":"PIN_CODE_DELIVERED"}']) {
    assert.throws(() => c.decodeVerification(new TextEncoder().encode(raw)), error => error.code === 'LINE_EMAIL_PROTOCOL_ERROR');
  }
});
