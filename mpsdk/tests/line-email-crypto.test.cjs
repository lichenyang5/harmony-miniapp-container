const assert = require('node:assert/strict');
const { test } = require('node:test');
const nodeCrypto = require('node:crypto');
const { createLoader } = require('./sdk-loader.cjs');

test('six-digit PIN preserves leading zeros and rejects biased uint32 candidates', () => {
  const candidates = [[255, 255, 255, 255], [0, 0, 0, 7]];
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined, {
    '@kit.CryptoArchitectureKit': { cryptoFramework: {
      createRandom: () => ({ generateRandomSync: size => {
        assert.equal(size, 4);
        return { data: Uint8Array.from(candidates.shift()) };
      } })
    } }
  });
  const { LineNativeEmailLoginCrypto } = load('main/ets/vendors/line/auth/LineEmailLoginCrypto');
  assert.equal(new LineNativeEmailLoginCrypto().createPin(), '000007');
  assert.equal(candidates.length, 0);
});

function nativeCrypto(hooks = {}) {
  return {
    AsyKeySpecItem: { X25519_PK_BN: 602, X25519_SK_BN: 601 },
    CryptoMode: { ENCRYPT_MODE: 1, DECRYPT_MODE: 2 },
    createRandom: () => ({ generateRandomSync: n => {
      if (hooks.failRandom) throw new Error('random failure');
      return { data: new Uint8Array(nodeCrypto.randomBytes(n)) };
    } }),
    createMd: name => {
      const hash = nodeCrypto.createHash(name.toLowerCase().replace('-', ''));
      return { updateSync: blob => hash.update(blob.data), digestSync: () => ({ data: new Uint8Array(hash.digest()) }) };
    },
    createAsyKeyGenerator: name => {
      assert.equal(name, 'X25519');
      return {
        generateKeyPair: async () => ({
          pubKey: { getAsyKeySpec: () => 9n },
          priKey: { getAsyKeySpec: () => 3n, clearMem: () => { hooks.nativeClears = (hooks.nativeClears ?? 0) + 1; } }
        }),
        convertKey: async (pub, pri) => ({ pubKey: pub, priKey: pri })
      };
    },
    AsyKeySpecType: { PRIVATE_KEY_SPEC: 1, PUBLIC_KEY_SPEC: 2 },
    createAsyKeyGeneratorBySpec: spec => ({
      generatePriKey: async () => {
        assert.equal(spec.specType, 1);
        assert.equal(spec.sk, 3n);
        return { spec, clearMem: () => { hooks.agreementPrivateClears =
          (hooks.agreementPrivateClears ?? 0) + 1; } };
      },
      generatePubKey: async () => {
        if (hooks.failPeerImport) throw new Error('peer import failed');
        assert.equal(spec.specType, 2);
        assert.equal(spec.pk, 9n);
        return { spec };
      }
    }),
    createKeyAgreement: name => {
      assert.equal(name, 'X25519');
      return { generateSecret: async () => ({ data: Uint8Array.from({ length: 32 }, (_, i) => i + 1) }) };
    },
    createSymKeyGenerator: name => {
      assert.equal(name, 'AES256');
      return { convertKey: async blob => ({ ...blob, clearMem: () => {
        hooks.symClears = (hooks.symClears ?? 0) + 1;
      } }) };
    },
    createCipher: name => {
      let mode;
      let key;
      let iv;
      return {
        init: async (m, k, params) => {
          if (hooks.failAesInit) throw new Error('AES init failure');
          mode = m; key = Buffer.from(k.data); iv = params?.iv?.data;
        },
        doFinal: async blob => {
          if (hooks.failAesFinal) throw new Error('AES final failure');
          const algorithm = name.includes('CBC') ? 'aes-256-cbc' : 'aes-256-ecb';
          const cipher = mode === 1 ? nodeCrypto.createCipheriv(algorithm, key, iv ?? null) :
            nodeCrypto.createDecipheriv(algorithm, key, iv ?? null);
          cipher.setAutoPadding(name.includes('PKCS7'));
          return { data: new Uint8Array(Buffer.concat([cipher.update(blob.data), cipher.final()])) };
        }
      };
    }
  };
}

function load(hooks) {
  const cryptoFramework = nativeCrypto(hooks);
  return createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.CryptoArchitectureKit': { cryptoFramework } })('main/ets/vendors/line/auth/LineEmailLoginCrypto');
}

test('RSA identity uses low UTF-16 bytes and PKCS1 type-2 block', async () => {
  const { LineNativeEmailLoginCrypto } = load();
  const { publicKey, privateKey } = nodeCrypto.generateKeyPairSync('rsa', { modulusLength: 1024 });
  const jwk = publicKey.export({ format: 'jwk' });
  const key = { keynm: 'key', nvalue: Buffer.from(jwk.n, 'base64url').toString('hex'),
    evalue: Buffer.from(jwk.e, 'base64url').toString('hex'), sessionKey: 'S' };
  const encoded = await new LineNativeEmailLoginCrypto().createIdentity(key, 'é@example.com', 'pw');
  const plain = nodeCrypto.privateDecrypt({ key: privateKey, padding: nodeCrypto.constants.RSA_NO_PADDING },
    Buffer.from(encoded.padStart(256, '0'), 'hex'));
  assert.equal(plain[0], 0);
  assert.equal(plain[1], 2);
  const separator = plain.indexOf(0, 2);
  assert.ok(separator >= 10);
  assert.ok(plain.subarray(2, separator).every(byte => byte !== 0));
  const payload = plain.subarray(separator + 1);
  const expected = '\x01S\x0dé@example.com\x02pw';
  assert.deepEqual(payload, Buffer.from(Array.from(expected, char => char.charCodeAt(0) & 255)));
});

test('E2EE secret and proof match independent AES and SHA256 vectors', async () => {
  const { LineNativeEmailLoginCrypto } = load();
  const crypto = new LineNativeEmailLoginCrypto();
  const created = await crypto.createE2ee('123456');
  assert.equal(created.publicKey.length, 32);
  assert.equal(created.privateKey.length, 32);
  const pinKey = nodeCrypto.createHash('sha256').update('123456').digest();
  const ecb = nodeCrypto.createCipheriv('aes-256-ecb', pinKey, null);
  ecb.setAutoPadding(false);
  assert.deepEqual(Buffer.from(created.secret), Buffer.concat([ecb.update(created.publicKey), ecb.final()]));
  const shared = Buffer.from(Array.from({ length: 32 }, (_, i) => i + 1));
  const key = nodeCrypto.createHash('sha256').update(shared).update('Key').digest();
  const ivHash = nodeCrypto.createHash('sha256').update(shared).update('IV').digest();
  const iv = Buffer.from(ivHash.subarray(0, 16).map((byte, i) => byte ^ ivHash[i + 16]));
  const chainCipher = nodeCrypto.createCipheriv('aes-256-cbc', key, iv);
  const chain = Buffer.concat([chainCipher.update('valid key chain'), chainCipher.final()]);
  const proof = await crypto.confirmE2ee(created.privateKey, created.publicKey, new Uint8Array(chain));
  const digest = nodeCrypto.createHash('sha256').update(chain).digest();
  const half = Buffer.from(digest.subarray(0, 16).map((byte, i) => byte ^ digest[i + 16]));
  const proofCipher = nodeCrypto.createCipheriv('aes-256-ecb', key, null);
  proofCipher.setAutoPadding(false);
  assert.deepEqual(Buffer.from(proof), Buffer.concat([proofCipher.update(half), proofCipher.final()]));
  await assert.rejects(() => crypto.confirmE2ee(created.privateKey, created.publicKey,
    new Uint8Array(chain.map((byte, i) => i === 0 ? byte ^ 0xff : byte))));
});

test('E2EE initialization releases the generated native private key when key extraction fails', async () => {
  const platform = nativeCrypto();
  let cleared = 0;
  platform.createAsyKeyGenerator = () => ({ generateKeyPair: async () => ({
    pubKey: { getAsyKeySpec() { throw new Error('platform key extraction failed'); } },
    priKey: { getAsyKeySpec: () => 3n, clearMem() { cleared++; } }
  }) });
  const { LineNativeEmailLoginCrypto } = createLoader(undefined, undefined, undefined, undefined,
    undefined, undefined, { '@kit.CryptoArchitectureKit': { cryptoFramework: platform } })
    ('main/ets/vendors/line/auth/LineEmailLoginCrypto');
  await assert.rejects(new LineNativeEmailLoginCrypto().createE2ee('123456'),
    error => error.code === 'LINE_EMAIL_CRYPTO_FAILED');
  assert.equal(cleared, 1, 'native private key must be released even when public key extraction fails');
});

test('AES init failure clears native key, exported E2EE private bytes and symmetric key', async () => {
  const hooks = { failAesInit: true };
  const { LineNativeEmailLoginCrypto } = load(hooks);
  const originalFill = Uint8Array.prototype.fill;
  let privateCleared = false;
  Uint8Array.prototype.fill = function (value, ...args) {
    if (this.length === 32 && this[0] === 3 && value === 0) privateCleared = true;
    return originalFill.call(this, value, ...args);
  };
  try {
    await assert.rejects(() => new LineNativeEmailLoginCrypto().createE2ee('123456'));
  } finally {
    Uint8Array.prototype.fill = originalFill;
  }
  assert.equal(hooks.nativeClears, 1);
  assert.equal(hooks.symClears, 1);
  assert.equal(privateCleared, true);
});

test('AES final failure also clears the generated private and symmetric keys', async () => {
  const hooks = { failAesFinal: true };
  const { LineNativeEmailLoginCrypto } = load(hooks);
  const originalFill = Uint8Array.prototype.fill;
  let privateCleared = false;
  Uint8Array.prototype.fill = function (value, ...args) {
    if (this.length === 32 && this[0] === 3 && value === 0) privateCleared = true;
    return originalFill.call(this, value, ...args);
  };
  try {
    await assert.rejects(() => new LineNativeEmailLoginCrypto().createE2ee('123456'));
  } finally {
    Uint8Array.prototype.fill = originalFill;
  }
  assert.equal(hooks.nativeClears, 1);
  assert.equal(hooks.symClears, 1);
  assert.equal(privateCleared, true);
});

test('RSA padding RNG failure clears the constructed plaintext block', async () => {
  const hooks = { failRandom: true };
  const { LineNativeEmailLoginCrypto } = load(hooks);
  const originalFill = Uint8Array.prototype.fill;
  let blockCleared = false;
  Uint8Array.prototype.fill = function (value, ...args) {
    if (this.length === 128 && this[1] === 2 && value === 0) blockCleared = true;
    return originalFill.call(this, value, ...args);
  };
  try {
    const { publicKey } = nodeCrypto.generateKeyPairSync('rsa', { modulusLength: 1024 });
    const jwk = publicKey.export({ format: 'jwk' });
    await assert.rejects(() => new LineNativeEmailLoginCrypto().createIdentity({
      keynm: 'k', nvalue: Buffer.from(jwk.n, 'base64url').toString('hex'),
      evalue: Buffer.from(jwk.e, 'base64url').toString('hex'), sessionKey: 'S'
    }, 'e@example.com', 'pw'));
  } finally {
    Uint8Array.prototype.fill = originalFill;
  }
  assert.equal(blockCleared, true);
});

test('peer X25519 import failure releases the reconstructed private key', async () => {
  const hooks = { failPeerImport: true };
  const { LineNativeEmailLoginCrypto } = load(hooks);
  const own = Uint8Array.from([3, ...Array(31).fill(0)]);
  const peer = Uint8Array.from([9, ...Array(31).fill(0)]);
  await assert.rejects(() => new LineNativeEmailLoginCrypto().confirmE2ee(own, peer,
    new Uint8Array(16)));
  assert.equal(hooks.agreementPrivateClears, 1);
});
