const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('Compact writer encodes signed i32 using the standard ZigZag wire vectors', () => {
  const { LineCompactWriter } = createLoader()('main/ets/vendors/line/network/LineCompactCodec');
  for (const [value, expected] of [
    [0, [0]], [-1, [1]], [1, [2]], [300, [0xd8, 4]],
    [-2147483648, [0xff, 0xff, 0xff, 0xff, 0x0f]],
    [2147483647, [0xfe, 0xff, 0xff, 0xff, 0x0f]]
  ]) {
    const writer = new LineCompactWriter();
    writer.integer(value);
    assert.deepEqual([...writer.result()], expected);
  }
});

test('Compact field writer preserves delta headers, full IDs and nested structure boundaries', () => {
  const load = createLoader();
  const { LineCompactWriter } = load('main/ets/vendors/line/network/LineCompactCodec');
  const writer = new LineCompactWriter();
  writer.field(1, 12);
  writer.field(1, 8);
  writer.field(6, 2, 2);
  writer.field(9, 8, 7);
  writer.field(20, 8);
  writer.field(0, 12);
  writer.field(-1, 5);
  assert.deepEqual([...writer.result()], [0x1c, 0x18, 0x42, 0x28, 8, 40, 12, 0, 5, 1]);
});

test('shared Compact reader retains the caller-specific protocol error', () => {
  const load = createLoader();
  const { LineCompactReader } = load('main/ets/vendors/line/network/LineCompactCodec');
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  const reader = new LineCompactReader(new Uint8Array(),
    () => new MiniAppError('LINE_RPC_PROTOCOL_ERROR', 'invalid LIFF response'));
  assert.throws(() => reader.byte(), error => error.code === 'LINE_RPC_PROTOCOL_ERROR');
  assert.throws(() => new LineCompactReader(new Uint8Array()).byte(),
    error => error.code === 'LINE_QR_PROTOCOL_ERROR');
});

test('fatal UTF-8 decoding preserves each caller protocol code and the native cause', () => {
  const load = createLoader();
  const { LineCompactReader } = load('main/ets/vendors/line/network/LineCompactCodec');
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  for (const [code, message] of [['LINE_QR_PROTOCOL_ERROR', 'invalid QR response'],
    ['LINE_RPC_PROTOCOL_ERROR', 'invalid LIFF response']]) {
    const reader = new LineCompactReader(Uint8Array.from([1, 255]), () => new MiniAppError(code, message));
    assert.throws(() => reader.string(), error => error instanceof MiniAppError && error.code === code &&
      error.message === message && error.originalCause instanceof TypeError);
  }
  assert.equal(new LineCompactReader(Uint8Array.from([2, 0xc3, 0xa9])).string(), 'é');
});

test('application exceptions require a complete body and retain private diagnostics only as a cause', () => {
  const { LineCompactCodec } = createLoader()('main/ets/vendors/line/network/LineCompactCodec');
  const method = 'refresh';
  const header = [0x82, 0x61, 1, method.length, ...Buffer.from(method)];
  const message = 'private server detail';
  // TApplicationException.message(field 1), type(field 2), unknown nested field 3.
  const body = [0x18, message.length, ...Buffer.from(message), 0x15, 12, 0x1c, 0, 0];
  const complete = Uint8Array.from([...header, ...body]);
  const decode = bytes => LineCompactCodec.response(bytes, method, 1,
    () => assert.fail('exception cannot be success'), () => assert.fail('exception is not a service result'));
  for (const bytes of [Uint8Array.from(header), complete.slice(0, -1),
    Uint8Array.from([...complete, 0]), Uint8Array.from([...header, 0x18, 10, 97]),
    Uint8Array.from([...header, 0x18, 1, 97, 0x08, 2, 1, 98, 0])]) {
    assert.throws(() => decode(bytes), error => error.code === 'LINE_QR_PROTOCOL_ERROR');
  }
  assert.throws(() => decode(complete), error => error.code === 'LINE_QR_APPLICATION_ERROR' &&
    error.message !== message && error.originalCause.message === message);
  assert.throws(() => decode(Uint8Array.from([...header, 0])), error => error.code === 'LINE_QR_APPLICATION_ERROR');
});

test('shared Compact reader handles LIFF string and integer lists and rejects a wrong element type', () => {
  const { LineCompactReader } = createLoader()('main/ets/vendors/line/network/LineCompactCodec');
  assert.deepEqual(new LineCompactReader(Uint8Array.from([0x18, 1, 97])).strings(), ['a']);
  assert.deepEqual(new LineCompactReader(Uint8Array.from([0x25, 2, 3])).integers(), [1, -2]);
  assert.throws(() => new LineCompactReader(Uint8Array.from([0x15, 2])).strings());
});

test('LIFF uses the shared empty-string writer on Harmony', () => {
  const load = createLoader({}, {}, undefined, {}, () => true, { DEBUG: false }, {
    '@kit.ArkTS': { util: { TextEncoder: class {
      encodeInto(value) {
        if (!value) throw new TypeError('Harmony empty input');
        return new TextEncoder().encode(value);
      }
    } } }
  });
  const { LineSubViewCodec } = load('main/ets/vendors/line/liff/LineSubViewCodec');
  assert.doesNotThrow(() => LineSubViewCodec.encode({
    liffId: 'child', msit: 'ticket', requestedUrl: 'https://liff.line.me/child', domain: ''
  }, 1));
});
