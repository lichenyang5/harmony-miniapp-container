const test = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const prefix = 'main/ets/vendors/line/';
const load = createLoader();

// Independent wire literals: no SDK writer or schema imported by these fixtures.
const str = value => [Buffer.byteLength(value), ...Buffer.from(value)];
const reply = (method, seq, fields) => Uint8Array.from([0x82, 0x41, seq, ...str(method), ...fields, 0]);
const call = (method, seq, fields) => Uint8Array.from([0x82, 0x21, seq, ...str(method), ...fields, 0]);
const client = send => {
  const { LineRegistrationClient } = load(prefix + 'registration/LineRegistrationClient');
  return new LineRegistrationClient({ send });
};

test('registration RPC diagnostics distinguish failure codes without logging private request or response data', async () => {
  const localLoad = createLoader();
  const { SdkLogger } = localLoad('main/ets/logging/SdkLogger');
  const { MiniAppError } = localLoad('main/ets/core/MiniAppError');
  const { LineRegistrationClient } = localLoad(prefix + 'registration/LineRegistrationClient');
  const logs = [];
  SdkLogger.install({ write: (level, event, details) => logs.push({ level, event, details }) });
  const transportFailure = new MiniAppError('LINE_RPC_NETWORK_ERROR', 'private-transport-text');
  const cases = [
    { send: async () => { throw transportFailure; }, code: 'LINE_RPC_NETWORK_ERROR', same: transportFailure },
    { send: async req => reply(req.method, 1, [0x1c, 0x15, 0, 0x18, ...str('private-server-text'), 0]), code: 'LINE_REGISTRATION_INTERNAL_ERROR' },
    { send: async () => new Uint8Array(), code: 'LINE_REGISTRATION_PROTOCOL_ERROR' },
    { send: async () => { throw Error('private-platform-text'); }, code: 'LINE_REGISTRATION_FAILED' }
  ];
  for (const item of cases) {
    logs.length = 0;
    let sends = 0;
    const c = new LineRegistrationClient({ send: async req => { sends++; return item.send(req); } });
    await assert.rejects(c.getPhoneMethods({ authSessionId: 'private-session', device: { udid: 'private-id', deviceModel: 'private-model' },
      userPhoneNumber: { phoneNumber: 'private-phone', countryCode: 'JP' } }), error => {
      if (item.same) assert.equal(error, item.same);
      return true;
    });
    assert.equal(sends, 1);
    assert.equal(logs.length, 2);
    assert.equal(logs[0].event, 'LineRegistration.rpcStarted');
    assert.equal(logs[1].event, 'LineRegistration.rpcFailed');
    const started = JSON.parse(logs[0].details), failed = JSON.parse(logs[1].details);
    assert.equal(failed.capability, 'getPhoneVerifMethodForRegistration');
    assert.equal(failed.code, item.code);
    assert.equal(failed.requestId, started.requestId);
    assert.equal(failed.sessionId, started.sessionId);
    assert.ok(failed.durationMs >= 0);
    assert.ok(!JSON.stringify(logs).includes('private-'));
  }
  logs.length = 0;
  await new LineRegistrationClient({ send: async req => reply(req.method, 1, [12, 0, 0x19, 0x15, 2, 0]) })
    .getPhoneMethods({ authSessionId: 'private-session', device: { udid: 'private-id', deviceModel: 'private-model' },
      userPhoneNumber: { phoneNumber: 'private-phone', countryCode: 'JP' } });
  assert.equal(logs.length, 2);
  assert.equal(logs[1].event, 'LineRegistration.rpcCompleted');
});

test('registration Talk calls keep the supplied trace and diagnose failures without exposing account credentials', async () => {
  const localLoad = createLoader();
  const { SdkLogger } = localLoad('main/ets/logging/SdkLogger');
  const { LineRegistrationDiagnostics } = localLoad(prefix + 'registration/LineRegistrationDiagnostics');
  const { LineRegistrationTalkClient } = localLoad(prefix + 'registration/LineRegistrationClient');
  const logs = [];
  SdkLogger.install({ write: (level, event, details) => logs.push({ event, ...JSON.parse(details) }) });
  const diagnostics = new LineRegistrationDiagnostics();
  const action = diagnostics.start('action', 'resumeFinalization');
  const talk = new LineRegistrationTalkClient({ send: async req => reply(req.method, 1,
    [12, 0, 0x18, ...str('private-mid'), 0xb8, ...str('JP'), 0]) }, 'private-account-token', 'PRIMARY', diagnostics);
  await talk.getProfile();
  const rejected = new LineRegistrationTalkClient({ send: async () => { throw Error('private-network-text'); } },
    'private-account-token', 'PRIMARY', diagnostics);
  await assert.rejects(rejected.getSettings(), { code: 'LINE_REGISTRATION_FAILED' });
  diagnostics.complete(action);
  assert.equal(new Set(logs.map(log => log.sessionId)).size, 1);
  assert.ok(logs.some(log => log.event === 'LineRegistration.rpcCompleted' && log.capability === 'getProfile'));
  assert.ok(logs.some(log => log.event === 'LineRegistration.rpcFailed' && log.capability === 'getSettings'));
  assert.ok(!JSON.stringify(logs).includes('private-'));
});

test('country, method lookup and pull SMS use their concrete schema fields', async () => {
  const phone = [0x18, ...str('123'), 0x18, ...str('JP'), 0];
  const cases = [
    ['getCountryInfo', { authSessionId: 's', simCard: { countryCode: 'JP', hni: '1', carrierName: 'c' } },
      'getCountryInfo', [0x18, ...str('s'), 0xac, 0x18, ...str('JP'), 0x18, ...str('1'), 0x18, ...str('c'), 0],
      [12, 0, 0x18, ...str('JP'), 0x11, 0x1a, 0x18, ...str('JP'), 0],
      { countryCode: 'JP', countryInEEA: true, countrySetOfEEA: ['JP'] }],
    ['getAllowedRegistrationMethod', { authSessionId: 's', countryCode: 'JP' }, 'getAllowedRegistrationMethod',
      [0x18, ...str('s'), 0x18, ...str('JP')], [12, 0, 0x15, 2, 0], { registrationMethod: 1 }],
    ['getPhoneMethods', { authSessionId: 's', device: { udid: 'id', deviceModel: 'm' },
      userPhoneNumber: { phoneNumber: '123', countryCode: 'JP' } }, 'getPhoneVerifMethodForRegistration',
      [0x1c, 0x18, ...str('s'), 0x1c, 0x18, ...str('id'), 0x18, ...str('m'), 0, 0x1c, ...phone, 0],
      [12, 0, 0x19, 0x35, 2, 4, 6, 0x18, ...str('+123'), 0],
      { availableMethods: [1, 2, 3], prettifiedPhoneNumber: '+123' }],
    ['requestCode', { authSessionId: 's', userPhoneNumber: { phoneNumber: '123', countryCode: 'JP' }, verifMethod: 2 },
      'requestToSendPhonePinCode', [0x1c, 0x18, ...str('s'), 0x1c, ...phone, 0x15, 4, 0],
      [12, 0, 0x19, 0x15, 2, 0], { availableMethods: [1] }],
    ['fetchPullSms', { authSessionId: 's', userPhoneNumber: { phoneNumber: '123', countryCode: 'JP' } },
      'fetchPhonePinCodeMsg', [0x1c, 0x18, ...str('s'), 0x1c, ...phone, 0],
      [12, 0, 0x18, ...str('PIN'), 0x18, ...str('456'), 0],
      { pinCodeMessage: 'PIN', destinationPhoneNumber: '456' }],
    ['lookupAvailableEap', 's', 'lookupAvailableEap', [0x1c, 0x18, ...str('s'), 0],
      [12, 0, 0x19, 0x15, 6, 0], { availableEap: [3] }]
  ];
  for (const [name, arg, method, body, result, expected] of cases) {
    const c = client(async req => {
      assert.equal(req.method, method);
      assert.deepEqual(req.body, call(method, 1, body));
      return reply(method, 1, result);
    });
    assert.deepEqual(await c[name](arg), expected);
  }
});

test('password wire name and nested hashing parameters normalize to Task1 interfaces', async () => {
  const success = [12, 0, 0x1c, 0x18, ...str('key'), 0x1c, 0x18, ...str('salt'),
    0x18, ...str('1:1:1'), 0x16, 64, 0, 0, 0x19, 0x1c, 0x15, 0,
    0x19, 0x18, ...str('pattern'), 0x18, ...str('notice'), 0, 0];
  const c = client(async req => {
    assert.deepEqual(req.body, call('getPasswordHashingParametersForPwdReg', 1, [0x1c, 0x18, ...str('s'), 0]));
    return reply(req.method, 1, success);
  });
  assert.deepEqual(await c.getPasswordParameters('s'), { params: { hmacKey: 'key', salt: 'salt', nrp: '1:1:1', dkLen: 32 },
    rules: [{ patterns: ['pattern'], message: 'notice' }] });
  const unknown = [...success]; unknown[unknown.indexOf(0x15) + 1] = 2;
  await assert.rejects(client(async req => reply(req.method, 1, unknown)).getPasswordParameters('s'),
    { code: 'LINE_REGISTRATION_RULE_UNSUPPORTED' });
});

test('Talk finalization uses initialization=2, special args IDs, and millisecond i64 agreement', async () => {
  const { LineRegistrationTalkClient } = load(prefix + 'registration/LineRegistrationClient');
  let seq = 0;
  const talk = new LineRegistrationTalkClient({ send: async req => {
    seq++;
    let body, fields;
    switch (req.method) {
      case 'getProfile': body = [0x15, 4]; fields = [12, 0, 0x18, ...str('mid'), 0xb8, ...str('JP'), 0]; break;
      case 'getPendingAgreements': body = []; fields = [12, 0, 0x19, 0x15, 94, 0]; break;
      case 'getConfigurations': body = [0x26, 0, 0x18, ...str(''), 0x18, ...str('JP'), 0x18, ...str('JP'),
        0x18, ...str(''), 0x15, 4]; fields = [12, 0, 0x16, 2, 0x1b, 0, 0]; break;
      case 'getSettings': body = [0x15, 4]; fields = [12, 0, 0x02, 40, 0x11, 0]; break;
      case 'updateSettingsAttributes2':
        if (seq === 5) body = [0x15, 18, 0x3a, 0x35, 12, 14, 26, 0x0c, 6, 0x02, 40, 0x11, 0x12, 0];
        else body = [0x15, 20, 0x3a, 0x15, 106, 0x0c, 6, 0x06, 160, 1, 246, 161, 171, 254, 249, 98, 0];
        fields = [10, 0, 0x05]; break;
      default: assert.fail(req.method);
    }
    assert.deepEqual(req.body, call(req.method, seq, body));
    return reply(req.method, seq, fields);
  } }, 'access');
  assert.deepEqual(await talk.getProfile(), { mid: 'mid', regionCode: 'JP' });
  assert.deepEqual(await talk.getPendingAgreements(), { pendingAgreements: [47] });
  assert.deepEqual(await talk.getConfigurations({ revision: 0, regionOfUsim: '', regionOfTelephone: 'JP',
    regionOfLocale: 'JP', carrier: '' }), { revision: 1, configMap: new Map() });
  assert.deepEqual(await talk.getSettings(), { privacySyncContacts: false, privacySearchByPhoneNumber: true });
  assert.deepEqual(await talk.updatePrivacy({ privacySyncContacts: false, privacySearchByPhoneNumber: true,
    privacySearchByUserid: false }, 9), []);
  assert.deepEqual(await talk.updateCountryAgreement('GDPR', 1700000000123, 10), []);
});

test('registration client exists with the complete typed phone interface', () => {
  const c = client(async () => new Uint8Array());
  for (const name of ['openSession', 'getCountryInfo', 'getAllowedRegistrationMethod', 'getPhoneMethods',
    'requestCode', 'verifyCode', 'fetchPullSms', 'waitPullSms', 'validateProfile', 'getPasswordParameters',
    'setPasswordHash', 'registerPhone']) assert.equal(typeof c[name], 'function', name);
});

test('openSession uses anonymous primary identity and nested empty metadata map', async () => {
  const c = client(async req => {
    assert.deepEqual(req.body, call('openSession', 1, [0x1c, 0x1b, 0, 0]));
    assert.equal(req.path, '/acct/pais/v1');
    assert.equal(req.role, 'PRIMARY');
    assert.equal(req.accessKind, 'NONE');
    assert.equal(req.sessionAccess, undefined);
    return reply('openSession', 1, [8, 0, ...str('session')]);
  });
  assert.equal(await c.openSession(new Map()), 'session');
});

test('registerPhone authSessionId is args field 2 and V3 credentials retain timing', async () => {
  const c = client(async req => {
    assert.deepEqual(req.body, call('registerPrimaryUsingPhoneWithTokenV3', 1, [0x28, ...str('s')]));
    return reply(req.method, 1, [12, 0, 0x18, ...str('v1'), 0x1c,
      0x18, ...str('access'), 0x18, ...str('refresh'), 0x16, 120,
      0x28, ...str('login'), 0x16, 2, 0, 0x18, ...str('mid'), 0]);
  });
  assert.deepEqual(await c.registerPhone('s'), { authToken: 'v1', mid: 'mid', tokenV3IssueResult: {
    accessToken: 'access', refreshToken: 'refresh', durationUntilRefreshInSec: 60,
    loginSessionId: 'login', tokenIssueTimeEpochSec: 1 } });
});

test('verify and long-poll bool fields live in headers; session is explicit only for poll', async () => {
  let count = 0;
  const c = client(async req => {
    count++;
    assert.equal(req.accessKind, count === 1 ? 'NONE' : 'REGISTRATION_SESSION');
    assert.equal(req.sessionAccess, count === 1 ? undefined : 's');
    assert.equal(req.path, count === 1 ? '/acct/pais/v1' : '/acct/lp/pais/v1');
    if (count === 2) assert.equal(req.timeoutMs, 60000);
    return reply(req.method, count, [12, 0, 0x12, 0x12, 0x11, 0]);
  });
  const req = { authSessionId: 's', userPhoneNumber: { phoneNumber: '123', countryCode: 'JP' } };
  const expected = { accountExist: false, sameUdidFromAccount: false, allowedToRegister: true };
  assert.deepEqual(await c.verifyCode({ ...req, pinCode: '123456' }), expected);
  assert.deepEqual(await c.waitPullSms(req), expected);
});

test('empty struct success is mandatory and differs from void Talk result', async () => {
  const c = client(async req => reply(req.method, 1, []));
  await assert.rejects(c.validateProfile({ authSessionId: 's', displayName: 'Name' }),
    { code: 'LINE_REGISTRATION_PROTOCOL_ERROR' });
  const good = client(async req => {
    assert.deepEqual(req.body, call('setHashedPassword', 1,
      [0x1c, 0x18, ...str('s'), 0x18, ...str('V2:hash'), 0]));
    return reply(req.method, 1, [12, 0, 0]);
  });
  await good.setPasswordHash({ authSessionId: 's', password: 'V2:hash' });
  const { LineRegistrationTalkClient } = load(prefix + 'registration/LineRegistrationClient');
  const talk = new LineRegistrationTalkClient({ send: async req => {
    assert.equal(req.path, '/S4'); assert.equal(req.accessKind, 'ACCOUNT');
    assert.equal(req.sessionAccess, 'account'); assert.equal(req.role, 'PRIMARY');
    assert.deepEqual(req.body, call('updateProfileAttributes', 1,
      [0x15, 18, 0x1c, 0x1b, 1, 0x5c, 4, 0x18, ...str('Name'), 0, 0]));
    return reply(req.method, 1, []);
  } }, 'account');
  await talk.updateName('Name', 9);
});

test('valid profile request is unwrapped and unknown fields are skipped without defaulting flags', async () => {
  const c = client(async req => {
    assert.deepEqual(req.body, call('validateProfile', 1, [0x18, ...str('s'), 0x18, ...str('Name')]));
    return reply(req.method, 1, [12, 0, 0x1b, 1, 0x88, ...str('unused'), ...str('value'), 0]);
  });
  await c.validateProfile({ authSessionId: 's', displayName: 'Name' });
  const incomplete = client(async req => reply(req.method, 1, [12, 0, 0x18, ...str('unknown'), 0]));
  // Field 1 is known and must not silently accept a string in place of a BOOL.
  await assert.rejects(incomplete.verifyCode({ authSessionId: 's', userPhoneNumber: {
    phoneNumber: '123', countryCode: 'JP' }, pinCode: '123456' }), { code: 'LINE_REGISTRATION_PROTOCOL_ERROR' });
  const absent = client(async req => reply(req.method, 1, [12, 0, 0]));
  assert.deepEqual(await absent.verifyCode({ authSessionId: 's', userPhoneNumber: {
    phoneNumber: '123', countryCode: 'JP' }, pinCode: '123456' }), {});
});

test('all AuthException codes and unknown codes are distinct from Talk errors', async () => {
  const codes = [[0,'INTERNAL_ERROR'], [1,'ILLEGAL_ARGUMENT'], [2,'VERIFICATION_FAILED'], [3,'NOT_FOUND'],
    [4,'RETRY_LATER'], [5,'HUMAN_VERIFICATION_REQUIRED'], [100,'INVALID_CONTEXT'], [101,'APP_UPGRADE_REQUIRED']];
  for (const [wire, suffix] of codes) {
    const value = wire * 2;
    const encoded = value < 128 ? [value] : [(value & 127) | 128, value >> 7];
    await assert.rejects(client(async req => reply(req.method, 1, [0x1c, 0x15, ...encoded, 0])).openSession(),
      error => error.code === `LINE_REGISTRATION_${suffix}` && error.wireCode === wire);
  }
  await assert.rejects(client(async req => reply(req.method, 1, [0x1c, 0x15, 84, 0])).openSession(),
    error => error.code === 'LINE_REGISTRATION_REJECTED' && error.wireCode === 42);
  const { LineRegistrationTalkClient } = load(prefix + 'registration/LineRegistrationClient');
  const talk = new LineRegistrationTalkClient({ send: async req =>
    reply(req.method, 1, [0x1c, 0x15, 238, 1, 0x18, ...str('private'), 0]) }, 'account');
  await assert.rejects(talk.getProfile(), error => error.code === 'LINE_REGISTRATION_TOKEN_REFRESH_REQUIRED' &&
    error.wireCode === 119 && error.service === 'talk' && !error.message.includes('private'));
});

test('application exceptions and conflicting success/error envelopes are rejected', async () => {
  const application = Uint8Array.from([0x82, 0x61, 1, ...str('openSession'), 0x18, ...str('private'), 0]);
  await assert.rejects(client(async () => application).openSession(), { code: 'LINE_REGISTRATION_APPLICATION_ERROR' });
  for (const bytes of [Uint8Array.from([...application, 1]),
    reply('openSession', 1, [8, 0, ...str('s'), 0x1c, 0x15, 2, 0])]) {
    await assert.rejects(client(async () => bytes).openSession(), { code: 'LINE_REGISTRATION_PROTOCOL_ERROR' });
  }
});

test('AuthException preserves challenge field 11 with stable code and no raw message', async () => {
  const c = client(async req => reply(req.method, 1, [0x1c, 0x15, 10, 0x18, ...str('private'),
    0x9c, 0x18, ...str('https://challenge.example'), 0x18, ...str('secret'), 0, 0]));
  await assert.rejects(c.openSession(new Map()), error => {
    assert.equal(error.code, 'LINE_REGISTRATION_HUMAN_VERIFICATION_REQUIRED');
    assert.equal(error.wireCode, 5);
    assert.deepEqual(error.webAuthDetails, { baseUrl: 'https://challenge.example', token: 'secret' });
    assert.ok(!error.message.includes('private')); return true;
  });
});

test('response correlation, duplicate results, trailing bytes and unknown enum remain fail closed', async () => {
  for (const bytes of [reply('wrong', 1, [8, 0, ...str('s')]),
    reply('openSession', 2, [8, 0, ...str('s')]),
    reply('openSession', 1, [8, 0, ...str('s'), 8, 0, ...str('s')]),
    Uint8Array.from([...reply('openSession', 1, [8, 0, ...str('s')]), 1])]) {
    await assert.rejects(client(async () => bytes).openSession(new Map()),
      { code: 'LINE_REGISTRATION_PROTOCOL_ERROR' });
  }
});

test('Compact long preserves signed millisecond timestamps and every safe-integer edge', () => {
  const { LineCompactWriter, LineCompactReader } = load(prefix + 'network/LineCompactCodec');
  for (const value of [0, 1700000000123, -1700000000123, Number.MAX_SAFE_INTEGER, -Number.MAX_SAFE_INTEGER]) {
    const writer = new LineCompactWriter();
    assert.equal(typeof writer.long, 'function');
    writer.long(value);
    const wire = [];
    let zz = BigInt(value) >= 0n ? BigInt(value) * 2n : -BigInt(value) * 2n - 1n;
    do { const byte = Number(zz & 127n); zz >>= 7n; wire.push(byte | (zz ? 128 : 0)); } while (zz);
    assert.deepEqual([...writer.result()], wire);
    assert.equal(new LineCompactReader(Uint8Array.from(wire)).long(), value);
  }
  for (const value of [1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => new LineCompactWriter().long(value));
  }
  assert.throws(() => new LineCompactReader(Uint8Array.from([0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x20])).long());
  assert.equal(new LineCompactReader(Uint8Array.from([0x2c])).listCount(12), 2);
  assert.throws(() => new LineCompactReader(Uint8Array.from([0x2c])).listCount(8));
  assert.throws(() => new LineCompactReader(Uint8Array.from([0xfc, 0x81, 0x20])).listCount(12));
});

test('country agreement preserves literal signed milliseconds and rejects zero or unsafe values', async () => {
  const { LineRegistrationTalkClient } = load(prefix + 'registration/LineRegistrationClient');
  for (const [timestamp, bytes] of [[1700000000123, [246, 161, 171, 254, 249, 98]],
    [-1700000000123, [245, 161, 171, 254, 249, 98]]]) {
    const talk = new LineRegistrationTalkClient({ send: async req => {
      assert.deepEqual(req.body, call('updateSettingsAttributes2', 1,
        [0x15, 0, 0x3a, 0x15, 106, 0x0c, 6, 0x06, 160, 1, ...bytes, 0]));
      return reply(req.method, 1, [10, 0, 0x05]);
    } }, 'access');
    assert.deepEqual(await talk.updateCountryAgreement('GDPR', timestamp), []);
  }
  let calls = 0;
  const talk = new LineRegistrationTalkClient({ send: async () => { calls++; return new Uint8Array(); } }, 'access');
  for (const timestamp of [0, -0, Number.MAX_SAFE_INTEGER + 1, -Number.MAX_SAFE_INTEGER - 1, 1.5, NaN, Infinity]) {
    assert.throws(() => talk.updateCountryAgreement('GDPR', timestamp),
      { code: 'LINE_REGISTRATION_ILLEGAL_ARGUMENT' });
  }
  assert.equal(calls, 0);
});
