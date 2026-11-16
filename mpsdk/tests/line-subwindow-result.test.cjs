const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

const method = 'storeSubWindowResult';
const request = { liffId: 'child-id', msit: 'ticket', mstVerifier: 'parent-verifier' };
function string(value) { const bytes = Buffer.from(value); return [bytes.length, ...bytes]; }
function reply(fields = [0], options = {}) {
  return Uint8Array.from([0x82, ((options.kind ?? 2) << 5) | 1, options.sequence ?? 1,
    ...string(options.method ?? method), ...fields]);
}
function failure(field, code) {
  const value = code * 2;
  return reply([(field << 4) | 12, 0x15, ...(value > 127 ? [value | 128, value >> 7] : [value]), 0, 0]);
}
function loader() {
  return createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } } });
}

test('store result encodes only msit and mstVerifier inside request field 1', () => {
  const { LineSubViewCodec } = loader()('main/ets/vendors/line/liff/LineSubViewCodec');
  assert.deepEqual(Array.from(LineSubViewCodec.encodeStoreResult(request, 1)),
    [0x82, 0x21, 1, ...string(method), 0x1c, 0x18, ...string('ticket'),
      0x18, ...string('parent-verifier'), 0, 0]);
});

test('store result accepts the official empty void result without a fabricated success field', () => {
  const { LineSubViewCodec } = loader()('main/ets/vendors/line/liff/LineSubViewCodec');
  assert.equal(LineSubViewCodec.decodeStoreResult(reply(), 1), undefined);
  assert.throws(() => LineSubViewCodec.decode(reply(), 1, method), e => e.code === 'LINE_RPC_PROTOCOL_ERROR');
});

test('store result validates the complete envelope and application exception body', () => {
  const { LineSubViewCodec } = loader()('main/ets/vendors/line/liff/LineSubViewCodec');
  const application = reply([0x18, ...string('private failure'), 0], { kind: 3 });
  for (const bytes of [reply().slice(0, -1), reply([0, 0]), reply([], { kind: 3 }),
    reply([0], { method: 'issueSubLiffView' }), reply([0], { sequence: 2 }),
    application.slice(0, -1), reply([0], { kind: 1 }), failure(1, 2).slice(0, -1)]) {
    assert.throws(() => LineSubViewCodec.decodeStoreResult(bytes, 1), e => e.code === 'LINE_RPC_PROTOCOL_ERROR');
  }
  assert.throws(() => LineSubViewCodec.decodeStoreResult(application, 1), e =>
    e.code === 'LINE_RPC_APPLICATION_ERROR' && !e.message.includes('private') && e.originalCause.message === 'private failure');
  assert.throws(() => LineSubViewCodec.decodeStoreResult(reply([0], { kind: 3 }), 1),
    e => e.code === 'LINE_RPC_APPLICATION_ERROR');
});

test('store result preserves LIFF and account failures', () => {
  const { LineSubViewCodec } = loader()('main/ets/vendors/line/liff/LineSubViewCodec');
  for (const [field, code, expected] of [[1, 2, 'LINE_LIFF_ERROR_2'], [2, 2, 'LINE_ACCOUNT_ERROR_2'],
    [2, 119, 'LINE_ACCOUNT_ERROR_119']]) {
    assert.throws(() => LineSubViewCodec.decodeStoreResult(failure(field, code), 1), e => e.code === expected);
  }
});

test('void success cannot hide a known exception field with the wrong wire type', () => {
  const { LineSubViewCodec } = loader()('main/ets/vendors/line/liff/LineSubViewCodec');
  for (const fields of [[0x15, 4, 0], [0x25, 238, 1, 0]]) {
    assert.throws(() => LineSubViewCodec.decodeStoreResult(reply(fields), 1),
      error => error.code === 'LINE_RPC_PROTOCOL_ERROR');
  }
  // An unrelated future field can still be skipped without inventing a success field.
  assert.equal(LineSubViewCodec.decodeStoreResult(reply([0x35, 4, 0]), 1), undefined);
});

test('store result prefers account transport and passes child LIFF ID without webpage credentials', async () => {
  const { LineSubViewService } = loader()('main/ets/vendors/line/liff/LineSubViewService');
  const calls = [];
  const service = new LineSubViewService({ account: { sendLiffRpc: async (...args) => {
    calls.push(args); return reply();
  } }, sendLiffRpc: async () => assert.fail('host transport must not override account'),
  issueSubLiffView: async () => assert.fail('issuance callback is unrelated') });
  assert.equal(await service.storeResult(request), undefined);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], method);
  assert.equal(calls[0][2], 'child-id');
  assert.equal(calls[0][3], 1);
  assert.ok(!Buffer.from(calls[0][1]).includes(Buffer.from('child-id')));
});

test('store result uses legacy binary transport and requires an account source', async () => {
  const { LineSubViewService } = loader()('main/ets/vendors/line/liff/LineSubViewService');
  let rpc;
  await new LineSubViewService({ sendLiffRpc: async value => { rpc = value; return reply(); } }).storeResult(request);
  assert.equal(rpc.method, method);
  assert.equal(rpc.path, '/LIFF1');
  assert.equal(rpc.liffId, 'child-id');
  assert.deepEqual(Object.keys(rpc).sort(), ['body', 'liffId', 'method', 'path']);
  await assert.rejects(new LineSubViewService({ issueSubLiffView: async () => ({}) }).storeResult(request),
    e => e.code === 'LINE_ACCOUNT_PROVIDER_REQUIRED');
});

test('account client accepts void success and refreshes 119 only once with the original account generation', async () => {
  const { LineLiffClient } = loader()('main/ets/vendors/line/liff/LineLiffClient');
  for (const rejected of [false, true]) {
    const calls = [];
    const client = new LineLiffClient({ getVersion: () => 7, requireAccessToken: () => 'account-token',
      sendAccountRpc: async rpc => { calls.push(rpc); return rejected && calls.length === 1 ? failure(2, 119) : reply(); },
      refreshRejectedToken: async (token, generation) => {
        assert.equal(token, 'account-token'); assert.equal(generation, 7);
      } });
    assert.deepEqual(await client.send(method, Uint8Array.from([1]), 'child-id', 1), reply());
    assert.equal(calls.length, rejected ? 2 : 1);
    assert.equal(calls[0].liffId, 'child-id');
    assert.equal(calls[0].accessToken, undefined);
  }
});

test('store retry does not cross account generations', async () => {
  const { LineLiffClient } = loader()('main/ets/vendors/line/liff/LineLiffClient');
  let generation = 1;
  let sends = 0;
  const client = new LineLiffClient({ getVersion: () => generation, requireAccessToken: () => 'account-token',
    sendAccountRpc: async () => { sends++; return failure(2, 119); },
    refreshRejectedToken: async () => { generation++; } });
  await assert.rejects(client.send(method, new Uint8Array(), 'child-id', 1), e => e.code === 'LINE_LOGIN_CANCELLED');
  assert.equal(sends, 1);
});

test('result service decodes the retried reply and does not refresh a second rejection', async () => {
  const load = loader();
  const { LineLiffClient } = load('main/ets/vendors/line/liff/LineLiffClient');
  const { LineSubViewService } = load('main/ets/vendors/line/liff/LineSubViewService');
  for (const rejectedAgain of [false, true]) {
    let sends = 0;
    let refreshes = 0;
    const client = new LineLiffClient({ getVersion: () => 1, requireAccessToken: () => 'account-token',
      sendAccountRpc: async () => { sends++; return sends === 1 || rejectedAgain ? failure(2, 119) : reply(); },
      refreshRejectedToken: async () => { refreshes++; } });
    const service = new LineSubViewService({ account: { sendLiffRpc: (...args) => client.send(...args) } });
    if (rejectedAgain) {
      await assert.rejects(service.storeResult(request), e => e.code === 'LINE_ACCOUNT_ERROR_119');
    } else {
      await service.storeResult(request);
    }
    assert.equal(sends, 2);
    assert.equal(refreshes, 1);
  }
});
