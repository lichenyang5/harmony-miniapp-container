const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function setup(responseCode = 200) {
  const calls = [];
  const services = [];
  let released = 0;
  const load = createLoader({}, {}, undefined, {}, undefined, undefined, {
    '@kit.ArkTS': { url: { URL } },
    '@kit.NetworkKit': { http: {
      RequestMethod: { GET: 'GET', POST: 'POST' },
      HttpDataType: { ARRAY_BUFFER: 1 }, HttpProtocol: { HTTP2: 2 },
      createHttp() { return {
        async request(target, options) {
          calls.push({ target, ...options });
          return { responseCode, result: Uint8Array.from([123, 125]).buffer };
        }, destroy() { released++; }
      }; }
    } }
  });
  const { LineHttpTransport } = load('main/ets/vendors/line/network/LineHttpTransport');
  return { calls, services, released: () => released,
    transport: new LineHttpTransport({ applicationHeader: 'ANDROIDSECONDARY',
      endpointFor: async service => { services.push(service); return 'https://legy.example'; } }) };
}

test('email authentication is binary POST while verification is GET with the verifier header', async () => {
  const s = setup();
  await s.transport.send({ path: '/api/v4p/rs', method: 'loginV2', body: Uint8Array.from([0x82]) });
  await s.transport.send({ path: '/LF1', method: 'verifyEmailPin', body: new Uint8Array(), sessionAccess: 'verifier' });
  assert.deepEqual(s.services, ['auth', 'verification']);
  assert.equal(s.calls[0].method, 'POST');
  assert.deepEqual(new Uint8Array(s.calls[0].extraData), Uint8Array.from([0x82]));
  assert.equal(s.calls[1].method, 'GET');
  assert.equal(s.calls[1].extraData, undefined);
  assert.equal(s.calls[1].header['X-Line-Access'], 'verifier');
  assert.equal(s.calls[1].header.Accept, 'application/json');
  assert.equal(s.released(), 2);
});

test('verification timeout HTTP 410 has a stable email-specific code and releases the request', async () => {
  const s = setup(410);
  await assert.rejects(s.transport.send({ path: '/LF1', method: 'verifyEmailPin',
    body: new Uint8Array(), sessionAccess: 'verifier' }),
  error => error.code === 'LINE_EMAIL_VERIFICATION_TIMEOUT');
  assert.equal(s.released(), 1);
});

test('email verification cannot be sent without a verifier and arbitrary paths remain rejected', async () => {
  const s = setup();
  for (const path of ['/LF1', '/api/v4p/arbitrary']) {
    await assert.rejects(s.transport.send({ path, method: 'anything', body: new Uint8Array() }));
  }
  assert.equal(s.calls.length, 0);
});

test('plain verification uses the APK Q path after the explicit E2EE rejection branch', async () => {
  const s = setup();
  await s.transport.send({ path: '/Q', method: 'verifyEmailPin', body: new Uint8Array(), sessionAccess: 'v' });
  assert.equal(s.calls[0].method, 'GET');
  assert.equal(new URL(s.calls[0].target).pathname, '/Q');
});
