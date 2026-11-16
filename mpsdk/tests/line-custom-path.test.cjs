const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

function resolver(response, headers) {
  const requests = [];
  let destroyed = 0;
  let receiveHeaders;
  const http = {
    RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'string' },
    createHttp: () => ({
      on: (_event, callback) => { receiveHeaders = callback; },
      request: async (address, options) => {
        requests.push({ address, options });
        if (headers) receiveHeaders(headers);
        if (response instanceof Error) throw response;
        return response;
      },
      destroy: () => { destroyed++; }
    })
  };
  const load = createLoader({}, {}, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } }, '@kit.NetworkKit': { http } });
  return { LineCustomPathResolver: load('main/ets/vendors/line/LineCustomPathResolver').LineCustomPathResolver,
    requests, get destroyed() { return destroyed; } };
}

test('official Custom Path resolves from the LINE launch field without forwarding user query', async () => {
  const f = resolver({ responseCode: 200,
    result: '<script>const liffUrlForLINEApp = "line://app/2007326019-vAg8J6Bp";</script>' });
  assert.equal(f.LineCustomPathResolver.isCustomPathUrl('https://miniapp.line.me/buruburudobutsu?c=line'), true);
  assert.equal(await f.LineCustomPathResolver.resolve('https://miniapp.line.me/buruburudobutsu?c=line#private'),
    '2007326019-vAg8J6Bp');
  assert.equal(f.requests[0].address, 'https://miniapp.line.me/buruburudobutsu');
  assert.equal(f.requests[0].options.method, 'GET');
  assert.equal(f.destroyed, 1);
});

test('resolver refuses nonofficial hosts, credentials, numeric IDs and invalid paths before networking', async () => {
  const f = resolver({ responseCode: 200, result: '' });
  for (const address of ['http://miniapp.line.me/game', 'https://miniapp.line.me.evil.example/game',
    'https://user:pass@miniapp.line.me/game', 'https://miniapp.line.me/2007326019-vAg8J6Bp',
    'https://miniapp.line.me/12345', 'https://miniapp.line.me/bad_', 'https://miniapp.line.me/a']) {
    assert.equal(f.LineCustomPathResolver.isCustomPathUrl(address), false, address);
    await assert.rejects(f.LineCustomPathResolver.resolve(address), { code: 'LINE_CUSTOM_PATH_INVALID' });
  }
  assert.equal(f.requests.length, 0);
});

test('resolver reports missing pages, changed page format and network failure without inventing an ID', async () => {
  for (const [result, code] of [
    [{ responseCode: 404, result: '' }, 'LINE_CUSTOM_PATH_NOT_FOUND'],
    [{ responseCode: 200, result: '<html>no launch field</html>' }, 'LINE_CUSTOM_PATH_RESPONSE_INVALID'],
    [new Error('offline'), 'LINE_CUSTOM_PATH_RESOLVE_FAILED']
  ]) {
    const f = resolver(result);
    await assert.rejects(f.LineCustomPathResolver.resolve('https://miniapp.line.me/unknown_app'), { code });
    assert.equal(f.destroyed, 1);
  }
});

test('resolver rejects redirect headers even if a later response contains a plausible ID', async () => {
  const f = resolver({ responseCode: 200,
    result: 'const liffUrlForLINEApp = "line://app/123456-abcdefg";' }, { Location: 'https://other.example/' });
  await assert.rejects(f.LineCustomPathResolver.resolve('https://miniapp.line.me/test_app'),
    { code: 'LINE_CUSTOM_PATH_RESOLVE_FAILED' });
  assert.equal(f.destroyed, 1);
});

test('resolver accepts the LIFF ID shape documented by LINE', async () => {
  const f = resolver({ responseCode: 200,
    result: 'const liffUrlForLINEApp = "line://app/123456-abcdefg";' });
  assert.equal(await f.LineCustomPathResolver.resolve('https://miniapp.line.me/test_app'), '123456-abcdefg');
});
