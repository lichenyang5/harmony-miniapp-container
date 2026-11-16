const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { spawnSync } = require('node:child_process');

const base = 'main/ets/vendors/line/registration/';
const parameters = { hmacKey: Buffer.from('independent HMAC key').toString('base64'),
  salt: Buffer.from('server salt').toString('base64'), nrp: '040101', dkLen: 32 };

function expected(password, params = parameters) {
  const value = parseInt(params.nrp, 16);
  const secret = crypto.createHmac('sha256', Buffer.from(params.hmacKey, 'base64'))
    .update(password, 'utf8').digest();
  const derived = crypto.scryptSync(secret, Buffer.from(params.salt, 'base64'), params.dkLen,
    { N: 2 ** (value >>> 16), r: (value >>> 8) & 255, p: value & 255, maxmem: 80 * 1024 * 1024 });
  return `$s0$${params.nrp}$${params.salt}$${derived.toString('base64')}`;
}

function source() {
  let scheduled = 0;
  const load = createLoader({}, {}, undefined, {}, () => true, { DEBUG: false }, {
    '@kit.ArkTS': { taskpool: {
      Task: class { constructor(fn, ...args) { this.fn = fn; this.args = args; } },
      async execute(task) { scheduled++; return task.fn(...task.args); }
    } }
  });
  return { load, scheduled: () => scheduled };
}

test('V2 matches independent Node HMAC/scrypt vectors including Unicode and whitespace', async () => {
  const { load, scheduled } = source();
  const implementation = new (load(base + 'LineRegistrationCrypto').LineNativeRegistrationPasswordCrypto)();
  for (const password of ['password', ' 密碼🔐é\n ', ' leading and trailing ', '']) {
    assert.equal(await implementation.hash(password, parameters, []), expected(password));
  }
  // Java String.getBytes(UTF_8) replaces an unpaired surrogate with ASCII '?'.
  assert.equal(await implementation.hash('\ud800', parameters, []), expected('?'));
  for (const params of [ { ...parameters, nrp: '060202', dkLen: 65 },
    { ...parameters, nrp: '0A0801', dkLen: 1 },
    { ...parameters, nrp: '0e0801' },
    { ...parameters, hmacKey: Buffer.alloc(100, 0xa5).toString('base64') } ]) {
    assert.equal(await implementation.hash('🧪\u0000abc', params, []), expected('🧪\u0000abc', params));
  }
  assert.equal(scheduled(), 9, 'each default hash is submitted to taskpool');
});

test('pure scrypt includes the RFC 7914 empty-input vector', () => {
  const { load } = source();
  const { lineRegistrationScrypt, lineRegistrationHmacSha256 } = load(base + 'LineRegistrationScrypt');
  assert.equal(Buffer.from(lineRegistrationScrypt(new Uint8Array(), new Uint8Array(), 16, 1, 1, 64)).toString('hex'),
    '77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442' +
    'fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906');
  assert.equal(Buffer.from(lineRegistrationHmacSha256(Buffer.alloc(20, 0x0b), Buffer.from('Hi There'))).toString('hex'),
    'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7');
});

test('invalid, overflow and excessive resource parameters fail rather than downgrade', async () => {
  const { load } = source();
  const implementation = new (load(base + 'LineRegistrationCrypto').LineNativeRegistrationPasswordCrypto)();
  for (const patch of [{ nrp: '000101' }, { nrp: '200101' }, { nrp: '80000101' },
    { nrp: '040001' }, { nrp: '040100' }, { nrp: '040101x' }, { nrp: '-40101' },
    { nrp: '110801' }, { nrp: '100101' }, { nrp: '0f08ff' }, { dkLen: 0 },
    { dkLen: 1.5 }, { dkLen: Infinity }, { dkLen: 2 ** 32 }, { dkLen: 1025 },
    { hmacKey: '%%%' }, { hmacKey: '' }, { salt: 'YQ===' }, { salt: 'YR==' }]) {
    await assert.rejects(implementation.hash('password', { ...parameters, ...patch }, []),
      error => error.code === 'LINE_REGISTRATION_CRYPTO_FAILED', JSON.stringify(patch));
  }
});

test('every regex is a full-string match and password is never trimmed', async () => {
  const { load } = source();
  const implementation = new (load(base + 'LineRegistrationCrypto').LineNativeRegistrationPasswordCrypto)();
  const rules = [{ patterns: ['(?=.*[A-Z]).{8,}', '[A-Za-z0-9 ]+'], message: 'private rule message' }];
  assert.equal(await implementation.hash(' Password1 ', parameters, rules), expected(' Password1 '));
  for (const password of ['Password1\n', 'password1', 'Password1!']) {
    await assert.rejects(implementation.hash(password, parameters, rules), error =>
      error.code === 'LINE_REGISTRATION_PASSWORD_INVALID' && !error.message.includes('private rule message'));
  }
  await assert.rejects(implementation.hash('ab', parameters, [{ patterns: ['a|b'], message: '' }]),
    error => error.code === 'LINE_REGISTRATION_PASSWORD_INVALID');
  assert.equal(await implementation.hash('🔐', parameters, [{ patterns: ['.'], message: '' }]), expected('🔐'));
});

test('invalid and unsupported Java regex syntax fails closed', async () => {
  const { load } = source();
  const implementation = new (load(base + 'LineRegistrationCrypto').LineNativeRegistrationPasswordCrypto)();
  for (const pattern of ['[', '(?i)abc', '\\p{L}+', '[a-z&&[^b]]+', 'a++', '\\Qtext\\E',
    '(a)\\1', '(?<=a)b', '(?>a)', '\\Aabc\\z', '[^]', '\\babc', '\\u{1f510}']) {
    await assert.rejects(implementation.hash('abc', parameters, [{ patterns: [pattern], message: 'private' }]),
      error => error.code === 'LINE_REGISTRATION_RULE_UNSUPPORTED', pattern);
  }
});

test('unsafe regex complexity is rejected before evaluation with an external process deadline', () => {
  // The child runs real source. Its OS-level timeout bounds RED even if RegExp.test pins its thread.
  const child = spawnSync(process.execPath, ['-e', `
    const assert = require('node:assert/strict');
    const { createLoader } = require(${JSON.stringify(require.resolve('./sdk-loader.cjs'))});
    const { lineRegistrationHash } = createLoader()(${JSON.stringify(base + 'LineRegistrationPassword')});
    const params = ${JSON.stringify(parameters)};
    for (const pattern of ['(a+)+b', '(a|aa)+b', '(?:a|aa)*b', 'a*a*a*a*b',
      'a{0,40}a{0,40}a{0,40}b', '(a?){40}a{40}', 'a+(?=a+b)', '(?=(?=a+)a+)a+',
      'a{999999999}']) {
      assert.throws(() => lineRegistrationHash('a'.repeat(40), params,
        [{ patterns: [pattern], message: '' }]), error =>
        error.code === 'LINE_REGISTRATION_RULE_UNSUPPORTED', pattern);
    }
    console.log('unsafe rules rejected');
  `], { encoding: 'utf8', timeout: 3000, windowsHide: true });
  assert.equal(child.error, undefined, child.error?.message);
  assert.equal(child.status, 0, child.stderr);
  assert.match(child.stdout, /unsafe rules rejected/);
});

test('bounded leading lookaheads and simple repeated password classes remain supported', async () => {
  const { load } = source();
  const implementation = new (load(base + 'LineRegistrationCrypto').LineNativeRegistrationPasswordCrypto)();
  const patterns = ['^(?=.{8,20}$)(?=.*[A-Z])(?=.*[0-9])[A-Za-z0-9]+$', '(?!.*x)[A-Za-z0-9]{8,20}'];
  assert.equal(await implementation.hash('Password1', parameters, [{ patterns, message: '' }]), expected('Password1'));
  await assert.rejects(implementation.hash('password1', parameters, [{ patterns, message: '' }]),
    error => error.code === 'LINE_REGISTRATION_PASSWORD_INVALID');
});

test('Java whitespace and dot semantics include explicit non-ASCII differences', async () => {
  const { load } = source();
  const implementation = new (load(base + 'LineRegistrationCrypto').LineNativeRegistrationPasswordCrypto)();
  for (const pattern of ['.', '\\s']) {
    await assert.rejects(implementation.hash('\u0085', parameters, [{ patterns: [pattern], message: '' }]),
      error => error.code === 'LINE_REGISTRATION_PASSWORD_INVALID');
  }
  await assert.rejects(implementation.hash('\u00a0', parameters, [{ patterns: ['\\s'], message: '' }]),
    error => error.code === 'LINE_REGISTRATION_PASSWORD_INVALID');
  assert.equal(await implementation.hash(' ', parameters, [{ patterns: ['\\s'], message: '' }]), expected(' '));
});

test('worker failure rejects without running a fallback hash', async () => {
  const load = createLoader({}, {}, undefined, {}, () => true, { DEBUG: false }, {
    '@kit.ArkTS': { taskpool: { Task: class {}, async execute() { throw Error('worker unavailable'); } } }
  });
  const implementation = new (load(base + 'LineRegistrationCrypto').LineNativeRegistrationPasswordCrypto)();
  await assert.rejects(implementation.hash('password', parameters, []),
    error => error.code === 'LINE_REGISTRATION_CRYPTO_FAILED');
});

test('device identity is persisted per host installation and failure cannot create ephemeral identity', () => {
  const stores = new Map();
  const context = { getApplicationContext() { return this; } };
  function loader(fail = false) {
    return createLoader({}, {}, undefined, {}, () => true, { DEBUG: false }, {
      '@kit.BasicServicesKit': { deviceInfo: { productModel: 'actual host model' } },
      '@kit.CryptoArchitectureKit': { cryptoFramework: { createRandom: () => ({
        generateRandomSync: size => ({ data: crypto.randomBytes(size) }) }) } },
      '@kit.ArkData': { preferences: { getPreferencesSync(host) {
        if (!stores.has(host)) stores.set(host, new Map());
        const values = stores.get(host);
        return { getSync: (key, fallback) => values.get(key) ?? fallback,
          putSync: (key, value) => values.set(key, value), flushSync() { if (fail) throw Error('disk'); } };
      } } }
    });
  }
  const first = loader()(base + 'LineRegistrationDevice').LineRegistrationDevice.get(context);
  const second = loader()(base + 'LineRegistrationDevice').LineRegistrationDevice.get(context);
  assert.deepEqual(first, second);
  assert.match(first.udid, /^[0-9a-f]{32}$/);
  assert.equal(first.deviceModel, 'actual host model');
  assert.notEqual(loader()(base + 'LineRegistrationDevice').LineRegistrationDevice.get({ getApplicationContext() { return this; } }).udid,
    first.udid);
  assert.throws(() => loader(true)(base + 'LineRegistrationDevice').LineRegistrationDevice.get({ getApplicationContext() { return this; } }),
    error => error.code === 'LINE_REGISTRATION_DEVICE_FAILED');
});
