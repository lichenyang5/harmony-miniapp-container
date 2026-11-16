const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const methods = {
  liff: ['getReturnUrlWithRequestTokenForMultiLiffLogin', 'getWebLoginDisallowedUrlForMultiLiffLogin'],
  browser: ['getReturnUrlWithRequestTokenForAutoLogin', 'getWebLoginDisallowedUrl']
};
const str = value => { const bytes = Buffer.from(value); return [bytes.length, ...bytes]; };
const reply = (source, fields, allowed = true, sequence = 7) => Uint8Array.from([
  0x82, 0x41, sequence, ...str(methods[source][allowed ? 0 : 1]), ...fields
]);
const loadCodec = () => createLoader()('main/ets/vendors/line/weblogin/LineWebLoginCodec').LineWebLoginCodec;

test('web login requests preserve the hooked URL and use source-specific context', () => {
  const codec = loadCodec();
  const hookedFullUrl = 'https://access.line.me/oauth2/v2.1/login?returnUri=%2Fx%3Fstate%3Dx%252By#/';
  for (const source of ['liff', 'browser']) for (const allowed of [true, false]) {
    const body = codec.encode(source, { hookedFullUrl }, allowed, 7);
    const context = source === 'browser' ? [0x21] : [0x2c, 0x1c, 0, 0];
    assert.deepEqual([...body], [0x82, 0x21, 7, ...str(methods[source][allowed ? 0 : 1]),
      0x1c, 0x18, ...str(hookedFullUrl), ...context, 0, 0]);
  }
});

test('web login success separates LIFF session from browser optional return URLs', () => {
  const codec = loadCodec();
  const fields = [0x0c, 0, 0x18, ...str('https://shop.example/callback'),
    0x18, ...str('second'), 0x18, ...str('third'), 0, 0];
  assert.deepEqual(codec.decode('liff', reply('liff', fields), true, 7), {
    returnUrl: 'https://shop.example/callback', sessionString: 'second', liffId: 'third'
  });
  assert.deepEqual(codec.decode('browser', reply('browser', fields, false), false, 7), {
    returnUrl: 'https://shop.example/callback'
  });
});

test('Channel permission carries consentUrl and LIFF sessionString in parameterMap', () => {
  const codec = loadCodec();
  const map = [2, 0x88, ...str('consentUrl'), ...str('https://access.line.me/consent'),
    ...str('sessionString'), ...str('session-a')];
  for (const source of ['liff', 'browser']) {
    const field = source === 'browser' ? 0x1c : 0x2c;
    const bytes = reply(source, [field, 0x15, 8, 0x2b, ...map, 0, 0]);
    assert.deepEqual(codec.decode(source, bytes, true, 7), {
      consentUrl: 'https://access.line.me/consent', sessionString: 'session-a'
    });
  }
});

test('only LIFF Talk exception field 3 maps to refresh rejection', () => {
  const codec = loadCodec();
  assert.throws(() => codec.decode('liff', reply('liff', [0x3c, 0x15, 0xee, 1, 0, 0]), true, 7),
    error => error.code === 'LINE_ACCOUNT_ERROR_119');
  assert.throws(() => codec.decode('browser', reply('browser', [0x1c, 0x15, 0xee, 1, 0, 0]), true, 7),
    error => error.code === 'LINE_CHANNEL_ERROR_119');
});

test('wire parser rejects malformed known fields, ambiguous results and stale envelopes', () => {
  const codec = loadCodec();
  const good = [0x0c, 0, 0x18, ...str('https://shop.example'), 0, 0];
  const cases = [reply('liff', good, true, 8), reply('browser', good),
    reply('liff', [0]), reply('liff', [0x01, 0, 0]),
    reply('liff', [0x0c, 0, 0x15, 2, 0, 0]),
    reply('liff', [...good.slice(0, -1), 0x1c, 0x15, 2, 0, 0]),
    Uint8Array.from([...reply('liff', good), 0]), reply('liff', good).slice(0, -1)];
  for (const bytes of cases) assert.throws(() => codec.decode('liff', bytes, true, 7),
    error => error.code === 'LINE_WEB_LOGIN_PROTOCOL_INVALID');
});

module.exports = { reply, str };
