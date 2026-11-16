const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

// Independent Compact fixture writer: fixed REPLY envelope and known schema fields.
function reply(fields, { method = 'issueSubLiffView', sequence = 1, kind = 2 } = {}) {
  const bytes = [0x82, (kind << 5) | 1, sequence, method.length, ...Buffer.from(method), ...fields];
  return new Uint8Array(bytes);
}
function string(value) { const b = Buffer.from(value); return [b.length, ...b]; }
function viewReply() {
  return reply([0x0c, 0, // success field 0, struct
    0x1c, 0x28, ...string('https://scanner.example/endpoint'), 0, // view.url
    0x18, ...string('context'), 0x18, ...string('child-access'), 0x18, ...string('child-feature'),
    0x28, ...string('123'), 0x18, ...string('id-token'),
    0x19, 0x18, ...string('profile'), // scopes
    0x78, ...string('child-id'), 0, 0]);
}

test('issueSubLiffView writes the Compact message and request with wire field IDs', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  const bytes = LineSubViewCodec.encode({ liffId: 'child-id', msit: 'ticket', requestedUrl: 'https://liff.line.me/child-id' }, 1);
  const expected = [0x82, 0x21, 1, ...string('issueSubLiffView'), 0x1c,
    0x18, ...string('child-id'), 0x1c, 0x1c, 0, 0, // context.none
    0x38, ...string('ticket'), 0x12, // subsequentLiff = false, field 6
    0x38, ...string('https://liff.line.me/child-id'), 0, 0];
  assert.deepEqual(Array.from(bytes), expected);
});

test('issueSubLiffView reads child credentials and scopes without treating them as parent credentials', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  const result = LineSubViewCodec.decode(viewReply(), 1);
  assert.equal(result.url, 'https://scanner.example/endpoint');
  assert.equal(result.liffId, 'child-id');
  assert.equal(result.accessToken, 'child-access');
  assert.equal(result.featureToken, 'child-feature');
  assert.deepEqual(result.scopes, ['profile']);
});

test('Compact rejects truncated, mismatched and exceptional responses with sanitized errors', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  for (const bytes of [viewReply().slice(0, -2), reply([0], { sequence: 2 }),
    reply([0], { method: 'wrongMethod' }), reply([0]), new Uint8Array([0x82])]) {
    assert.throws(() => LineSubViewCodec.decode(bytes, 1));
  }
  const failure = reply([0x1c, 0x15, 4, 0x18, ...string('private error'), 0, 0]);
  assert.throws(() => LineSubViewCodec.decode(failure, 1), e => e.code === 'LINE_LIFF_ERROR_2' && !e.message.includes('private'));
});

test('view.type reads field 1 as a string and preserves missing, empty and unknown values', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  for (const method of ['issueLiffView', 'issueSubLiffView']) {
    for (const viewType of [undefined, 'FULL', 'TALL', '', 'FUTURE']) {
      const fields = viewType === undefined ? [] : [0x18, ...string(viewType)];
      const result = LineSubViewCodec.decode(reply([0x0c, 0, 0x1c, ...fields,
        viewType === undefined ? 0x28 : 0x18, ...string('https://app.example'),
        0x3c, 0x18, ...string('unknown nested field'), 0, 0, 0, 0], { method }), 1, method);
      assert.equal(result.viewType, viewType);
      assert.equal(result.url, 'https://app.example');
    }
  }
});

test('view.type rejects known field 1 with non-string wire types', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  for (const method of ['issueLiffView', 'issueSubLiffView']) {
    for (const fields of [[0x15, 2], [0x11], [0x1c, 0]]) {
      const bytes = reply([0x0c, 0, 0x1c, ...fields,
        0x18, ...string('https://app.example'), 0, 0, 0], { method });
      assert.throws(() => LineSubViewCodec.decode(bytes, 1, method),
        error => error.code === 'LINE_RPC_PROTOCOL_ERROR');
    }
  }
});

test('subview issuance snapshots view.type without defaulting empty or unknown strings', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } } });
  const { LineSubViewService } = load('main/ets/vendors/line/liff/LineSubViewService');
  for (const viewType of [undefined, 'FULL', 'TALL', '', 'FUTURE']) {
    const issued = { url: 'https://child.example', accessToken: 'access', featureToken: 'feature',
      contextToken: 'context', viewType };
    const service = new LineSubViewService({ issueSubLiffView: async () => issued });
    const result = await service.issue({ liffId: 'child-id', msit: 'ticket',
      requestedUrl: 'https://liff.line.me/child-id' });
    assert.equal(result.viewType, viewType);
    issued.viewType = 'changed';
    assert.equal(result.viewType, viewType);
  }
  const service = new LineSubViewService({ issueSubLiffView: async () => ({
    url: 'https://child.example', accessToken: 'access', featureToken: 'feature',
    contextToken: 'context', viewType: 1 }) });
  await assert.rejects(service.issue({ liffId: 'child-id', msit: 'ticket',
    requestedUrl: 'https://liff.line.me/child-id' }), error => error.code === 'LINE_SUBVIEW_INVALID');
});

function consentReply({ method = 'issueLiffView', code = 3, resultField = 1, payload = true,
  consentUrl = 'https://access.line.me/dialog/consent?private=ticket', channelId = '2012241482' } = {}) {
  return reply([(resultField << 4) | 0x0c, 0x15, code * 2,
    0x18, ...string('private service message'),
    ...(payload ? [0x1c, 0x3c, 0x18, ...string(channelId), 0x18, ...string(consentUrl), 0, 0] : []),
    0, 0], { method });
}

test('LIFF consent response retains the official channel and URL for native authorization', () => {
  const load = createLoader();
  const { LineSubViewCodec } = load('main/ets/vendors/line/liff/LineSubViewCodec');
  const { LineConsentRequiredError } = load('main/ets/vendors/line/liff/LineConsentRequiredError');
  for (const method of ['issueLiffView', 'issueSubLiffView']) {
    assert.throws(() => LineSubViewCodec.decode(consentReply({ method }), 1, method), error => {
      assert.ok(error instanceof LineConsentRequiredError);
      assert.equal(error.code, 'LINE_LIFF_ERROR_3');
      assert.equal(error.channelId, '2012241482');
      assert.equal(error.consentUrl, 'https://access.line.me/dialog/consent?private=ticket');
      assert.equal(error.originalCause, undefined);
      assert.ok(!error.message.includes('private'));
      assert.ok(!error.message.includes('https:'));
      return true;
    });
  }
});

test('missing or unrelated LIFF payload cannot become a usable consent request', () => {
  const load = createLoader();
  const { LineSubViewCodec } = load('main/ets/vendors/line/liff/LineSubViewCodec');
  const { LineConsentRequiredError } = load('main/ets/vendors/line/liff/LineConsentRequiredError');
  for (const options of [{ payload: false }, { consentUrl: '' },
    { code: 2 }, { resultField: 2 }]) {
    assert.throws(() => LineSubViewCodec.decode(consentReply(options), 1, 'issueLiffView'), error => {
      assert.ok(!(error instanceof LineConsentRequiredError));
      assert.equal(error.code, options.resultField === 2 ? 'LINE_ACCOUNT_ERROR_3' :
        `LINE_LIFF_ERROR_${options.code ?? 3}`);
      return true;
    });
  }
  assert.throws(() => LineSubViewCodec.decode(consentReply().slice(0, -1), 1, 'issueLiffView'),
    error => error.code === 'LINE_RPC_PROTOCOL_ERROR');
  assert.throws(() => LineSubViewCodec.decode(consentReply({ channelId: '' }), 1, 'issueLiffView'),
    error => error instanceof LineConsentRequiredError && error.consentUrl.length > 0);
});

test('account RPC preserves consent requirements without refreshing or retrying account login', async () => {
  const load = createLoader();
  const { LineLiffClient } = load('main/ets/vendors/line/liff/LineLiffClient');
  const { LineConsentRequiredError } = load('main/ets/vendors/line/liff/LineConsentRequiredError');
  let requests = 0;
  const client = new LineLiffClient({ getVersion: () => 1, requireAccessToken: () => 'native-token',
    sendAccountRpc: async () => { requests++; return consentReply(); },
    refreshRejectedToken: async () => { assert.fail('app consent must not refresh account credentials'); } });
  await assert.rejects(client.send('issueLiffView', new Uint8Array(), 'app-id', 1), error =>
    error instanceof LineConsentRequiredError && error.channelId === '2012241482');
  assert.equal(requests, 1);
});

test('main and child LIFF application exceptions require a complete body before returning their stable error', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  const message = 'private LIFF application failure';
  const body = [0x18, ...string(message), 0x15, 12, 0x1c, 0, 0];
  for (const method of ['issueLiffView', 'issueSubLiffView']) {
    const complete = reply(body, { method, kind: 3 });
    const duplicate = reply([0x18, ...string(message), 0x08, 2, ...string('duplicate'), 0], { method, kind: 3 });
    for (const bytes of [reply([], { method, kind: 3 }), complete.slice(0, -1),
      Uint8Array.from([...complete, 0]), duplicate, reply([0x18, 1, 255, 0], { method, kind: 3 })]) {
      assert.throws(() => LineSubViewCodec.decode(bytes, 1, method), error => error.code === 'LINE_RPC_PROTOCOL_ERROR');
    }
    assert.throws(() => LineSubViewCodec.decode(complete, 1, method), error => error.code === 'LINE_RPC_APPLICATION_ERROR' &&
      !error.message.includes(message) && error.originalCause.message === message);
    assert.throws(() => LineSubViewCodec.decode(reply([0], { method, kind: 3 }), 1, method),
      error => error.code === 'LINE_RPC_APPLICATION_ERROR' && error.originalCause === undefined);
  }
});

test('subLiffView.url overrides the ordinary view URL independently of wire order', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  const bytes = reply([0x0c, 0, 0xbc, 0x28, ...string('https://child.example/scan'), 0x71, 0,
    0x0c, 2, 0x28, ...string('https://ordinary.example'), 0, 0, 0]);
  const result = LineSubViewCodec.decode(bytes, 1);
  assert.equal(result.url, 'https://child.example/scan');
  assert.equal(result.hideCloseButton, true);
});

function subViewReply(fields) {
  return reply([0x0c, 0, 0xbc, ...fields, 0, 0, 0]);
}

test('subLiffView reads presentation, close position and label using independent wire values', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  for (const presentationType of [1, 2, 3]) {
    for (const closeButtonPosition of [1, 2]) {
      const result = LineSubViewCodec.decode(subViewReply([
        0x15, presentationType * 2, // field 1: I32
        0x18, ...string('https://child.example/scan'), // field 2: URL
        0x35, closeButtonPosition * 2, // field 5: I32
        0x18, ...string('完成'), // field 6: BINARY
        0x31 // field 9: true
      ]), 1);
      assert.equal(result.presentationType, presentationType);
      assert.equal(result.closeButtonPosition, closeButtonPosition);
      assert.equal(result.closeButtonLabel, '完成');
      assert.equal(result.hideCloseButton, true);
      assert.equal(result.url, 'https://child.example/scan');
    }
  }
});

test('subLiffView leaves missing or unknown enums undefined and still reads later fields', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  const missing = LineSubViewCodec.decode(subViewReply([]), 1);
  for (const field of ['presentationType', 'closeButtonPosition', 'closeButtonLabel', 'hideCloseButton']) {
    assert.equal(missing[field], undefined);
  }
  for (const value of [[0], [1], [0xc6, 1]]) { // 0, -1, 99
    const result = LineSubViewCodec.decode(subViewReply([
      0x15, ...value, 0x45, ...value,
      0x18, ...string(''), 0x1c, 0x18, ...string('unknown nested field'), 0,
      0x22 // unknown field 7 does not shift hideCloseButton at field 9
    ]), 1);
    assert.equal(result.presentationType, undefined);
    assert.equal(result.closeButtonPosition, undefined);
    assert.equal(result.closeButtonLabel, '');
    assert.equal(result.hideCloseButton, false);
  }
});

test('subLiffView skips mismatched wire types without consuming subsequent fields', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  const result = LineSubViewCodec.decode(subViewReply([
    0x18, ...string('wrong presentation type'),
    0x48, ...string('wrong close position type'),
    0x15, 2, // close label incorrectly sent as I32
    0x28, ...string('unknown field 8'), 0x31 // unknown field 11
  ]), 1);
  assert.equal(result.presentationType, undefined);
  assert.equal(result.closeButtonPosition, undefined);
  assert.equal(result.closeButtonLabel, undefined);
  const later = LineSubViewCodec.decode(subViewReply([
    0x18, ...string('wrong presentation type'), 0x45, 4,
    0x18, ...string('Close'), 0x32
  ]), 1);
  assert.equal(later.closeButtonPosition, 2);
  assert.equal(later.closeButtonLabel, 'Close');
  assert.equal(later.hideCloseButton, false);
});

test('subLiffView rejects malformed presentation integers and labels with the LIFF protocol error', () => {
  const { LineSubViewCodec } = createLoader()('main/ets/vendors/line/liff/LineSubViewCodec');
  for (const fields of [
    [0x15, 0xff, 0xff, 0xff, 0xff, 0x10],
    [0x55, 0xff, 0xff, 0xff, 0xff, 0x10],
    [0x68, 1, 0xff], // invalid UTF-8
    [0x68, 127, 0x61] // truncated BINARY
  ]) {
    assert.throws(() => LineSubViewCodec.decode(subViewReply(fields), 1),
      error => error.code === 'LINE_RPC_PROTOCOL_ERROR');
  }
});

test('subview issuance uses the shared account before legacy host callbacks', async () => {
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL } } });
  const { LineSubViewService } = load('main/ets/vendors/line/liff/LineSubViewService');
  const methods = [];
  const service = new LineSubViewService({
    account: { sendLiffRpc: async (method, body) => {
      methods.push(method);
      assert.ok(body instanceof Uint8Array);
      return viewReply();
    } },
    issueSubLiffView: async () => { throw new Error('legacy callback used'); }
  });
  const result = await service.issue({ liffId: 'child-id', msit: 'ticket',
    requestedUrl: 'https://liff.line.me/child-id' });
  assert.deepEqual(methods, ['issueSubLiffView']);
  assert.equal(result.accessToken, 'child-access');
});
