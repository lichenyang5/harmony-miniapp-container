const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('native X25519 source preserves the 32-byte little-endian public key', async () => {
  let cleared = false;
  let generated = 0;
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined, {
    '@kit.CryptoArchitectureKit': { cryptoFramework: {
      AsyKeySpecItem: { X25519_PK_BN: 602, X25519_SK_BN: 601 },
      createAsyKeyGenerator: name => {
        generated++;
        assert.equal(name, 'X25519');
        return { generateKeyPair: async () => ({
          pubKey: { getAsyKeySpec: item => { assert.equal(item, 602); return 0x1234n; } },
          priKey: { getAsyKeySpec: item => { assert.equal(item, 601); return 0x5678n; },
            clearMem: () => { cleared = true; } }
        }) };
      }
    } }
  });
  const { LineNativeQrKeySource } = load('main/ets/vendors/line/auth/LineQrKeySource');
  const pair = await new LineNativeQrKeySource().create();
  assert.deepEqual(Array.from(pair.publicKey.slice(0, 3)), [0x34, 0x12, 0]);
  assert.deepEqual(Array.from(pair.privateKey.slice(0, 3)), [0x78, 0x56, 0]);
  assert.equal(pair.publicKey.length, 32);
  assert.equal(cleared, true);
  const concurrent = await Promise.all([
    new LineNativeQrKeySource().create(), new LineNativeQrKeySource().create()
  ]);
  assert.equal(generated, 1);
  assert.deepEqual(concurrent[0].publicKey, pair.publicKey);
  pair.publicKey.fill(0);
  pair.privateKey.fill(0);
  const reused = await new LineNativeQrKeySource().create();
  assert.equal(reused.publicKey[0], 0x34);
  assert.equal(reused.privateKey[0], 0x78);
});

test('native QR private key is cleared when key spec extraction fails', async () => {
  let cleared = 0;
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined, {
    '@kit.CryptoArchitectureKit': { cryptoFramework: {
      AsyKeySpecItem: { X25519_PK_BN: 602, X25519_SK_BN: 601 },
      createAsyKeyGenerator: () => ({ generateKeyPair: async () => ({
        pubKey: { getAsyKeySpec: () => { throw new Error('spec unavailable'); } },
        priKey: { clearMem: () => { cleared++; } }
      }) })
    } }
  });
  const { LineNativeQrKeySource } = load('main/ets/vendors/line/auth/LineQrKeySource');
  await assert.rejects(new LineNativeQrKeySource().create());
  assert.equal(cleared, 1);
});

test('HTTP transport sends binary Compact RPC with distinct poll session authorization', async () => {
  const requests = [];
  let destroyed = 0;
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined, {
    '@kit.ArkTS': { url: { URL } },
    '@kit.NetworkKit': { http: {
      RequestMethod: { POST: 'POST' }, HttpDataType: { ARRAY_BUFFER: 2 }, HttpProtocol: { HTTP2: 1 },
      createHttp: () => ({
        request: async (target, options) => {
          requests.push({ target, options });
          return { responseCode: 200, result: Uint8Array.from([0x82, 0x41]).buffer };
        },
        destroy: () => { destroyed++; }
      })
    } }
  });
  const { LineHttpTransport } = load('main/ets/vendors/line/network/LineHttpTransport');
  const transport = new LineHttpTransport({
    endpointFor: async () => 'https://legy.example/', applicationHeader: 'real-app-header'
  });
  const result = await transport.send({ path: '/acct/lp/lgn/sq/v1', method: 'checkQrCodeVerified',
    body: Uint8Array.from([1, 2, 3]), sessionAccess: 'qr-session', liffId: 'child-id', timeoutMs: 2000 });
  assert.deepEqual(Array.from(result), [0x82, 0x41]);
  assert.equal(requests[0].target, 'https://legy.example/acct/lp/lgn/sq/v1');
  assert.equal(requests[0].options.header['X-Line-Access'], 'qr-session');
  assert.equal(requests[0].options.header['X-Line-Application'], 'real-app-header');
  assert.equal(requests[0].options.header['X-Line-Liff-Id'], 'child-id');
  assert.deepEqual(Array.from(new Uint8Array(requests[0].options.extraData)), [1, 2, 3]);
  assert.equal(destroyed, 1);
});
