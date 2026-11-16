const test = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const prefix = 'main/ets/vendors/line/network/';
function setup(response, supportRoles = true) {
  const sent = [];
  const http = { RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { ARRAY_BUFFER: 3 },
    HttpProtocol: { HTTP2: 2 }, createHttp() { return {
      async request(target, options) { sent.push({ target, options }); return response; }, destroy() {} }; } };
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.NetworkKit': { http }, '@kit.ArkTS': { url: { URL } } });
  const { LineHttpTransport } = load(prefix + 'LineHttpTransport');
  const connection = { applicationHeader: 'ANDROIDSECONDARY\t26.15.1\tAndroid OS\t14',
    clientHeaders: { 'User-Agent': 'Line/26.15.1', 'X-LAL': 'en_SG' },
    async endpointFor() { return 'https://legy.example'; } };
  if (supportRoles) connection.applicationHeaderFor = role =>
    `${role === 'PRIMARY' ? 'ANDROID' : 'ANDROIDSECONDARY'}\t26.15.1\tAndroid OS\t14`;
  return { transport: new LineHttpTransport(connection), sent, load, connection };
}
const req = (path = '/acct/pais/v1', accessKind = 'NONE', sessionAccess) => ({
  path, method: 'test', body: new Uint8Array([1]), role: 'PRIMARY', accessKind, sessionAccess
});

test('explicit roles are immutable and primary requires a role-aware connection', async () => {
  const { transport, sent, connection } = setup({ responseCode: 200, result: new ArrayBuffer(0) });
  await transport.send(req());
  assert.equal(sent[0].options.header['X-Line-Application'], 'ANDROID\t26.15.1\tAndroid OS\t14');
  assert.equal(connection.applicationHeader, 'ANDROIDSECONDARY\t26.15.1\tAndroid OS\t14');
  assert.equal(transport.applicationHeaderFor('PRIMARY'), sent[0].options.header['X-Line-Application']);
  assert.equal(sent[0].options.header['X-Line-Access'], undefined);
  await assert.rejects(setup({ responseCode: 200, result: new ArrayBuffer(0) }, false).transport.send(req()),
    { code: 'LINE_CONNECTION_CONFIG_REQUIRED' });
});

test('registration session and account identity are accepted only for their explicit paths', async () => {
  const { transport, sent } = setup({ responseCode: 200, result: new ArrayBuffer(0) });
  await transport.send(req('/acct/lp/pais/v1', 'REGISTRATION_SESSION', 'session'));
  await transport.send(req('/S4', 'ACCOUNT', 'account'));
  assert.deepEqual(sent.map(s => s.options.header['X-Line-Access']), ['session', 'account']);
  for (const invalid of [req('/acct/pais/v1', 'ACCOUNT', 'token'), req('/acct/pais/v1', 'NONE', 'token'),
    req('/acct/lp/pais/v1', 'ACCOUNT', 'token'), req('/acct/lp/pais/v1', 'NONE'),
    req('/S4', 'NONE'), req('/S4', 'ACCOUNT'), req('/S4', 'mystery', 'token'),
    { ...req(), role: 'mystery' }, { ...req(), accessKind: undefined }, { ...req(), role: undefined }]) {
    await assert.rejects(transport.send(invalid), { code: 'LINE_CONNECTION_CONFIG_REQUIRED' });
  }
  assert.equal(sent.length, 2);
});

test('explicit account identity on existing routes requires a valid role while legacy stays secondary', async () => {
  for (const path of ['/LIFF1', '/CH4', '/EXT/auth/tokenrefresh/v1']) {
    const { transport, sent } = setup({ responseCode: 200, result: new ArrayBuffer(0) });
    for (const role of [undefined, 'unknown']) {
      await assert.rejects(transport.send({ ...req(path, 'ACCOUNT', 'account'), role }),
        { code: 'LINE_CONNECTION_CONFIG_REQUIRED' });
    }
    assert.equal(sent.length, 0);
    for (const role of ['PRIMARY', 'SECONDARY']) {
      await transport.send({ ...req(path, 'ACCOUNT', 'account'), role });
    }
    await transport.send({ path, method: 'legacy', body: new Uint8Array(), sessionAccess: 'legacy-account' });
    assert.deepEqual(sent.map(item => item.options.header['X-Line-Application'].split('\t')[0]),
      ['ANDROID', 'ANDROIDSECONDARY', 'ANDROIDSECONDARY']);
    assert.deepEqual(sent.map(item => item.options.header['X-Line-Access']), ['account', 'account', 'legacy-account']);
  }
});

test('PAIS/S4 demand exact effective 200 while legacy secondary keeps 2xx contract', async () => {
  for (const response of [{ responseCode: 201 }, { responseCode: 200, header: { 'x-lc': '403' } },
    { responseCode: 200, header: { 'X-LC': '-1' } }]) {
    const { transport } = setup({ ...response, result: new ArrayBuffer(0) });
    await assert.rejects(transport.send(req()), { code: 'LINE_RPC_HTTP_FAILED' });
    await assert.rejects(transport.send(req('/S4', 'ACCOUNT', 'account')), { code: 'LINE_RPC_HTTP_FAILED' });
  }
  const legacy = setup({ responseCode: 201, result: new ArrayBuffer(0) });
  await legacy.transport.send({ path: '/acct/lgn/sq/v1', method: 'createSession', body: new Uint8Array() });
});

test('invalid X-LC is ignored and Retry-After has positive bounded lifetime per host', async t => {
  for (const value of ['unknown', '2147483648']) {
    await setup({ responseCode: 200, header: { 'X-LC': value }, result: new ArrayBuffer(0) }).transport.send(req());
  }
  let now = 1000;
  t.mock.method(Date, 'now', () => now);
  const { transport, connection, sent } = setup({ responseCode: 503, header: { 'Retry-After': '1' },
    result: new ArrayBuffer(0) });
  await assert.rejects(transport.send(req()), { code: 'LINE_RPC_HTTP_FAILED' });
  connection.endpointFor = async () => 'https://other.example';
  await assert.rejects(transport.send(req()), { code: 'LINE_RPC_HTTP_FAILED' });
  connection.endpointFor = async () => 'https://legy.example';
  await assert.rejects(transport.send(req()), { code: 'LINE_RPC_RETRY_LATER' });
  now += 1000;
  await assert.rejects(transport.send(req()), { code: 'LINE_RPC_HTTP_FAILED' });
  assert.equal(sent.length, 3);
  for (const value of ['0', '-1', 'tomorrow', 'Infinity']) {
    const invalid = setup({ responseCode: 503, header: { 'Retry-After': value }, result: new ArrayBuffer(0) });
    await assert.rejects(invalid.transport.send(req()), { code: 'LINE_RPC_HTTP_FAILED' });
    await assert.rejects(invalid.transport.send(req()), { code: 'LINE_RPC_HTTP_FAILED' });
    assert.equal(invalid.sent.length, 2);
  }
});

test('503 Retry-After blocks subsequent attempts to the same host without automatic retry', async () => {
  const { transport, sent } = setup({ responseCode: 503, header: { 'Retry-After': '30' }, result: new ArrayBuffer(0) });
  await assert.rejects(transport.send(req()), { code: 'LINE_RPC_HTTP_FAILED' });
  await assert.rejects(transport.send(req()), { code: 'LINE_RPC_RETRY_LATER' });
  assert.equal(sent.length, 1);
});

test('conn-info supplies primary and default secondary application headers without tabs in release', () => {
  const { load } = setup({});
  const { LineConnInfoConnection } = load(prefix + 'LineConnInfoConnection');
  const connection = new LineConnInfoConnection({ androidRelease: '1\t4', locale: 'en_SG', localeCountry: 'SG' });
  assert.equal(connection.applicationHeader, 'ANDROIDSECONDARY\t26.15.1\tAndroid OS\t14');
  assert.equal(connection.applicationHeaderFor('PRIMARY'), 'ANDROID\t26.15.1\tAndroid OS\t14');
  assert.throws(() => connection.applicationHeaderFor('unknown'), { code: 'LINE_CONNECTION_CONFIG_REQUIRED' });
});
