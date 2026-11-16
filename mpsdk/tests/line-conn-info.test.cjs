const assert = require('node:assert/strict');
const { test } = require('node:test');
const crypto = require('node:crypto');
const { createLoader } = require('./sdk-loader.cjs');

class PlatformURL extends URL { get params() { return this.searchParams; } }
function load() {
  return createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL } } })('main/ets/vendors/line/network/LineConnInfoConnection');
}
const profile = { androidRelease: '14', locale: 'en_SG', localeCountry: 'SG',
  simCountry: 'SG', profileCountry: '', carrier: '52501' };

test('conn-info request follows APK R4 query and selects the lowest-priority LEGY TLS server', async () => {
  const { LineConnInfoConnection } = load();
  const addresses = [];
  const fetcher = { async get(address) {
    addresses.push(address);
    return JSON.stringify({ time: Math.floor(Date.now() / 1000), expire: 3600,
      payload: { servers: { legy: { wifi: [
        { host: 'backup.line-apps.com', port: 443, priority: 2, secure: 'tls' },
        { host: 'primary.line-apps.com', port: 443, priority: 1, secure: 'tls' }
      ] } } } });
  } };
  const connection = new LineConnInfoConnection(profile, fetcher);
  assert.equal(await connection.endpointFor('login'), 'https://primary.line-apps.com');
  assert.equal(await connection.endpointFor('liff'), 'https://primary.line-apps.com');
  assert.equal(addresses.length, 1);
  const request = new URL(addresses[0]);
  assert.equal(request.origin, 'https://cix.line-apps.com');
  assert.equal(request.pathname, '/R4');
  assert.equal(request.searchParams.get('type'), 'Android_OS');
  assert.equal(request.searchParams.get('version'), '26.15.1');
  assert.equal(request.searchParams.get('regions'), 'SG--SG');
  assert.equal(request.searchParams.get('carrier'), '52501');
  const salt = Buffer.from('4c605effdf3dfc9f217d48174020569180dc2338a5772a80ed0aaa01bcd0a08f', 'hex');
  const expected = crypto.createHash('md5').update('Android_OS26.15.1SG--SG' +
    request.searchParams.get('time') + '52501').update(salt).digest('hex');
  assert.equal(request.searchParams.get('key'), expected);
  assert.equal(connection.applicationHeader, 'ANDROIDSECONDARY\t26.15.1\tAndroid OS\t14');
  assert.equal(connection.clientHeaders['X-LAL'], 'en_SG');
});

test('conn-info tries both APK hosts and falls back to bundled LEGY when unavailable', async () => {
  const { LineConnInfoConnection } = load();
  const addresses = [];
  const connection = new LineConnInfoConnection(profile, { async get(address) {
    addresses.push(new URL(address).host);
    throw new Error('network unavailable');
  } });
  assert.equal(await connection.endpointFor('poll'), 'https://legy.line-apps.com');
  assert.deepEqual(addresses, ['cix.line-apps.com', 'ci.line-apps.com']);
});

test('conn-info ignores malformed server entries without discarding a valid LEGY candidate', async () => {
  const { LineConnInfoConnection } = load();
  let calls = 0;
  const connection = new LineConnInfoConnection(profile, { async get() {
    calls++;
    return JSON.stringify({ payload: { servers: { legy: { wifi: [
      null, 17, 'not a server', false, [], {},
      { host: 'invalid.line-apps.com', port: 80, priority: 0, secure: 'tls' },
      { host: 'primary.line-apps.com', port: 443, priority: 1, secure: 'tls' }
    ] } } } });
  } });
  assert.equal(await connection.endpointFor('login'), 'https://primary.line-apps.com');
  assert.equal(await connection.endpointFor('liff'), 'https://primary.line-apps.com');
  assert.equal(calls, 1);
});
