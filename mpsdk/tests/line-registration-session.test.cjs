const assert = require('node:assert/strict');
const { test, afterEach } = require('node:test');
const accounts = [];
afterEach(() => { for (const account of accounts.splice(0)) account.logout(); });
const { createLoader } = require('./sdk-loader.cjs');
const base = 'main/ets/vendors/line/';
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };

function harness(patch = {}) {
  const values = new Map();
  const load = createLoader({}, {}, undefined, undefined, undefined, undefined, {
    '@kit.ArkData': { preferences: { getPreferencesSync: () => ({
      getSync: (key, value) => values.get(key) ?? value, putSync: (key, value) => values.set(key, value),
      flushSync() {}, deleteSync: key => values.delete(key)
    }) } }
  });
  const calls = [];
  const client = {
    openSession: async () => { calls.push('open'); return 'private-session'; },
    getCountryInfo: async () => ({ countryCode: 'US', countrySetOfEEA: ['DE'] }),
    lookupAvailableEap: async () => ({}), getAllowedRegistrationMethod: async () => ({ registrationMethod: 1 }),
    getPhoneMethods: async () => ({ availableMethods: [1, 2, 3], prettifiedPhoneNumber: '+1 555' }),
    requestCode: async () => ({ availableMethods: [1, 2, 3] }),
    verifyCode: async () => ({ accountExist: false, allowedToRegister: true }),
    validateProfile: async () => {}, getPasswordParameters: async () => ({ params: {}, rules: [] }),
    setPasswordHash: async () => {}, registerPhone: async () => {
      calls.push('create'); return { mid: 'new-user', tokenV3IssueResult: { accessToken: 'private-access',
        refreshToken: 'private-refresh', loginSessionId: 'private-login', durationUntilRefreshInSec: 600 } };
    }, ...patch.client
  };
  let savedPrivacy = {};
  const talk = {
    updateName: async () => { calls.push('name'); }, getProfile: async () => ({ mid: 'new-user', regionCode: 'US' }),
    getPendingAgreements: async () => ({ pendingAgreements: [] }),
    getConfigurations: async () => { calls.push('config'); return {}; }, getSettings: async () => { calls.push('settings'); return savedPrivacy; },
    updatePrivacy: async p => { savedPrivacy = p; calls.push(['privacy', p]); return []; },
    updateCountryAgreement: async (...args) => { calls.push(['country', ...args]); return []; }, ...patch.talk
  };
  const { LineAccountManager } = load(base + 'auth/LineAccountManager');
  const credential = { mid: 'old-user', accessToken: 'old-token', refreshToken: 'old-refresh', certificate: '',
    loginSessionId: '', durationUntilRefreshInSec: 600, metaData: new Map() };
  const runner = { login: async () => credential, cancel() {} };
  const options = { persistent: true, storageContext: {}, registration: { client, crypto: { hash: async () => 'private-hash' },
    device: { udid: 'stable', deviceModel: 'actual' }, monotonicNow: () => 1, talkFactory: () => talk, ...patch.registration } };
  const create = () => { const account = new LineAccountManager(runner, 'model', 'model', patch.transport ?? { applicationHeaderFor: role => role, send: async () => { throw Error('unexpected RPC'); } }, { persistent: true, storageContext: {} }, undefined, options.registration); accounts.push(account); return account; };
  return { load, create, values, calls, client, talk };
}
async function start(h) {
  const account = h.create(), states = [];
  const session = account.startPhoneRegistration(s => states.push(s));
  session.result.catch(() => {});
  await tick();
  return { account, session, states };
}
async function password(session) {
  await session.submitPhoneNumber('555'); await session.requestVerification(1);
  await session.verifyCode('123456'); await session.validateProfile('New name');
}

for (const method of [1, 2]) {
  test(`verification method ${method} sends the exact server-normalized phone in send and verify requests`, async () => {
    const requests = [], normalized = '+81 70-0000-0000';
    const h = harness({ client: {
      getPhoneMethods: async request => {
        requests.push(['lookup', request.userPhoneNumber.phoneNumber]);
        return { availableMethods: [1, 2, 3], prettifiedPhoneNumber: normalized };
      },
      requestCode: async request => { requests.push(['send', request.userPhoneNumber.phoneNumber]); return { availableMethods: [1, 2, 3] }; },
      verifyCode: async request => { requests.push(['verify', request.userPhoneNumber.phoneNumber]); return { accountExist: false, allowedToRegister: true }; }
    } }), logs = [];
    const { SdkLogger } = h.load('main/ets/logging/SdkLogger');
    SdkLogger.install({ write: (level, event, details) => logs.push({ event, ...JSON.parse(details) }) });
    const { session } = await start(h);
    await session.selectCountry('JP');
    await session.submitPhoneNumber('07000000000');
    await session.requestVerification(method); await session.verifyCode('private-code');
    assert.deepEqual(requests, [['lookup', '07000000000'], ['send', normalized], ['verify', normalized]]);
    assert.equal(session.getState().prettifiedPhoneNumber, normalized);
    assert.ok(logs.some(log => log.event === 'LineRegistration.phoneContextReady'));
    assert.equal(logs.filter(log => log.event === 'LineRegistration.phoneContextUsed').length, 2);
    assert.ok(logs.some(log => log.event === 'LineRegistration.verificationChannelSelected' && log.capability === (method === 1 ? 'SMS' : 'IVR')));
    const output = JSON.stringify(logs);
    for (const secret of ['07000000000', normalized, 'private-code']) assert.ok(!output.includes(secret));
    session.cancel();
  });
}

test('PULL requests use the latest server-normalized phone after resubmission', async () => {
  const phones = [], replies = ['first-canonical', 'second-canonical'];
  const h = harness({ client: {
    getPhoneMethods: async () => ({ availableMethods: [3], prettifiedPhoneNumber: replies.shift() }),
    fetchPullSms: async request => { phones.push(request.userPhoneNumber.phoneNumber); return { destinationPhoneNumber: 'destination', pinCodeMessage: 'message' }; },
    waitPullSms: async request => { phones.push(request.userPhoneNumber.phoneNumber); return { accountExist: false, allowedToRegister: true }; }
  } });
  const { session } = await start(h);
  await session.submitPhoneNumber('first-input');
  await session.submitPhoneNumber('second-input');
  await session.startPullSms();
  assert.deepEqual(phones, ['second-canonical', 'second-canonical']);
  session.cancel();
});

test('missing or empty server-normalized phone cannot enter verification or fall back to raw input', async () => {
  for (const prettifiedPhoneNumber of [undefined, '', null]) {
    let sends = 0;
    const h = harness({ client: {
      getPhoneMethods: async () => ({ availableMethods: [1], prettifiedPhoneNumber }),
      requestCode: async () => { sends++; return { availableMethods: [1] }; }
    } });
    const { session } = await start(h);
    await assert.rejects(session.submitPhoneNumber('raw-input'), { code: 'LINE_REGISTRATION_PROTOCOL_ERROR' });
    assert.equal(session.getState().stage, 'phoneInput');
    await assert.rejects(session.requestVerification(1), { code: 'LINE_REGISTRATION_INVALID_STATE' });
    assert.equal(sends, 0);
    session.cancel();
  }
});

test('registration actions log initialization, local rejection, stage transitions and cancellation with one trace', async () => {
  const h = harness(), logs = [];
  const { SdkLogger } = h.load('main/ets/logging/SdkLogger');
  SdkLogger.install({ write: (level, event, details) => logs.push({ level, event, ...JSON.parse(details) }) });
  const { session } = await start(h);
  await assert.rejects(session.submitPhoneNumber(''), e => e.code === 'LINE_REGISTRATION_ILLEGAL_ARGUMENT');
  await session.submitPhoneNumber('private-phone');
  session.cancel(); session.cancel();
  assert.ok(logs.some(log => log.event === 'LineRegistration.actionCompleted' && log.capability === 'initialize'));
  assert.ok(logs.some(log => log.event === 'LineRegistration.actionFailed' && log.capability === 'submitPhoneNumber' &&
    log.code === 'LINE_REGISTRATION_ILLEGAL_ARGUMENT'));
  assert.ok(logs.some(log => log.event === 'LineRegistration.stageChanged' && log.capability === 'verification'));
  assert.equal(logs.filter(log => log.event === 'LineRegistration.cancelled').length, 1);
  assert.equal(logs.filter(log => log.event === 'LineRegistration.released').length, 1);
  assert.equal(new Set(logs.map(log => log.sessionId)).size, 1);
  assert.ok(!JSON.stringify(logs).includes('private-'));
});

test('account manager shares a local registration trace between initialization and the real RPC client', async () => {
  const h = harness({ registration: { client: undefined }, transport: {
    applicationHeaderFor: role => role, send: async () => { throw Error('private-network-error'); }
  } }), logs = [];
  const { SdkLogger } = h.load('main/ets/logging/SdkLogger');
  SdkLogger.install({ write: (level, event, details) => logs.push({ event, ...JSON.parse(details) }) });
  const { session } = await start(h);
  await assert.rejects(session.result, e => e.code === 'LINE_REGISTRATION_FAILED');
  const rpc = logs.find(log => log.event === 'LineRegistration.rpcFailed');
  const action = logs.find(log => log.event === 'LineRegistration.actionFailed');
  assert.equal(rpc.capability, 'openSession');
  assert.equal(action.capability, 'initialize');
  assert.equal(rpc.sessionId, action.sessionId);
  assert.notEqual(rpc.requestId, action.requestId);
  assert.ok(!JSON.stringify(logs).includes('private-'));
});

test('registration reserves the account slot synchronously and existing ready credentials survive', async () => {
  const h = harness(), a = h.create();
  await a.startQrLogin(() => {});
  assert.throws(() => a.startPhoneRegistration(() => {}), e => e.code === 'LINE_REGISTRATION_ACCOUNT_CONFLICT');
  assert.equal(a.requireAccessToken(), 'old-token');
  const b = h.create(), session = b.startPhoneRegistration(() => {}); session.result.catch(() => {});
  assert.throws(() => b.startPhoneRegistration(() => {}), e => e.code === 'LINE_LOGIN_IN_PROGRESS');
  await assert.rejects(b.startQrLogin(() => {}), e => e.code === 'LINE_LOGIN_IN_PROGRESS');
  await assert.rejects(session.result, e => e.code === 'LINE_REGISTRATION_ACCOUNT_CONFLICT');
  assert.equal(h.calls.length, 0); a.logout(); b.logout();
});

test('server admission and existing-account verification cannot reach creation', async () => {
  for (const response of [{ accountExist: true, allowedToRegister: true }, { accountExist: false, allowedToRegister: false }, {}]) {
    const h = harness({ client: { verifyCode: async () => response } }), { account, session } = await start(h);
    await session.submitPhoneNumber('555'); await session.requestVerification(1);
    await assert.rejects(session.verifyCode('code'));
    await assert.rejects(session.createAccount('secret'));
    assert.ok(!h.calls.includes('create')); session.cancel(); account.logout();
  }
});

test('EAP-only recommended country keeps country selection and rechecks an explicitly selected country', async () => {
  const requests = [];
  const h = harness({ client: { getAllowedRegistrationMethod: async request => {
    requests.push(request);
    return { registrationMethod: request.countryCode === 'JP' ? 1 : 2 };
  } } });
  const { session } = await start(h);
  let settled = false;
  session.result.then(() => { settled = true; }, () => { settled = true; });
  await tick();
  assert.equal(session.getState().stage, 'countrySelection');
  assert.equal(session.getState().errorCode, 'LINE_REGISTRATION_UNSUPPORTED');
  assert.equal(settled, false);
  await assert.rejects(session.submitPhoneNumber('555'), e => e.code === 'LINE_REGISTRATION_INVALID_STATE');
  await assert.rejects(session.selectCountry('US'), e => e.code === 'LINE_REGISTRATION_UNSUPPORTED');
  assert.equal(session.getState().stage, 'countrySelection');
  await session.selectCountry('JP');
  assert.equal(session.getState().stage, 'phoneInput');
  assert.equal(session.getState().countryCode, 'JP');
  assert.equal(session.getState().errorCode, undefined);
  assert.equal(h.calls.filter(call => call === 'open').length, 1);
  assert.deepEqual(requests.map(request => request.authSessionId), Array(3).fill('private-session'));
  assert.ok(!h.calls.includes('create'));
  session.cancel();
});

test('unknown registration method remains a fatal protocol error instead of admitting a phone country', async () => {
  for (const registrationMethod of [undefined, 99]) {
    const h = harness({ client: { getAllowedRegistrationMethod: async () => ({ registrationMethod }) } });
    const { session } = await start(h);
    await assert.rejects(session.result, e => e.code === 'LINE_REGISTRATION_PROTOCOL_ERROR');
    assert.equal(session.getState().stage, 'failed');
    assert.equal(session.getState().countryCode, undefined);
    assert.ok(!h.calls.includes('create'));
  }
});

test('cancelled create retains exclusivity, saves late pending credentials and never resurrects UI', async () => {
  const d = deferred(), h = harness({ client: { registerPhone: () => d.promise } });
  const { account, session, states } = await start(h); await password(session);
  const creating = session.createAccount('password'); await tick();
  await assert.rejects(session.createAccount('duplicate'));
  session.cancel(); const count = states.length;
  await assert.rejects(session.result, e => e.code === 'LINE_REGISTRATION_CANCELLED');
  await assert.rejects(account.startQrLogin(() => {}), e => e.code === 'LINE_LOGIN_IN_PROGRESS');
  d.resolve({ mid: 'new-user', tokenV3IssueResult: { accessToken: 'private-access', refreshToken: 'refresh', durationUntilRefreshInSec: 600 } });
  await assert.rejects(creating, e => e.code === 'LINE_REGISTRATION_CANCELLED');
  assert.equal(states.length, count); assert.equal(account.getAccountId(), undefined);
  assert.throws(() => account.requireAccessToken(), e => e.code === 'LINE_REGISTRATION_INCOMPLETE');
  await assert.rejects(account.restoreSession(), e => e.code === 'LINE_REGISTRATION_INCOMPLETE');
  const stored = JSON.parse([...h.values.values()][0]); assert.equal(stored.stage, 'pendingFinalization');
  const resumed = account.startPhoneRegistration(() => {}); resumed.result.catch(() => {}); await tick();
  await resumed.submitPrivacy({ privacySyncContacts: false, privacySearchByPhoneNumber: true });
  await resumed.result; assert.equal(account.getAccountId(), 'new-user'); assert.equal(h.calls.filter(c => c === 'open').length, 1);
  assert.ok(!JSON.stringify(states).includes('private')); account.logout();
});

test('logout invalidates late create identity and ambiguous creation never retries', async () => {
  const d = deferred(), h = harness({ client: { registerPhone: () => d.promise } });
  const { account, session } = await start(h); await password(session);
  const creating = session.createAccount('secret'); await tick(); account.logout();
  d.resolve({ mid: 'late', tokenV3IssueResult: { accessToken: 'late', refreshToken: 'late', durationUntilRefreshInSec: 600 } });
  await assert.rejects(creating); assert.equal(h.values.size, 0);
  const h2 = harness({ client: { registerPhone: async () => { throw Error('lost response secret'); } } });
  const s = await start(h2); await password(s.session);
  await assert.rejects(s.session.createAccount('secret'), e => e.code === 'LINE_REGISTRATION_CREATION_UNCERTAIN');
  await assert.rejects(s.session.createAccount('secret'), e => e.code === 'LINE_REGISTRATION_INVALID_STATE');
  assert.equal(s.states.at(-1).stage, 'creationUncertain'); s.session.cancel(); s.account.logout();
});

test('challenge is private in state and public rejection, presenter completion only permits explicit retry', async () => {
  const h = harness(); const { LineRegistrationError } = h.load(base + 'registration/LineRegistrationError');
  h.client.requestCode = async () => { throw new LineRegistrationError({ code: 5, webAuthDetails: { baseUrl: 'https://private', token: 'private-token' } }); };
  const { account, session, states } = await start(h); await session.submitPhoneNumber('555');
  await assert.rejects(session.requestVerification(1), e => e.code === 'LINE_REGISTRATION_HUMAN_VERIFICATION_REQUIRED' && !e.webAuthDetails && !e.originalCause);
  assert.equal(states.at(-1).stage, 'challengeRequired'); assert.ok(!JSON.stringify(states).includes('private'));
  await assert.rejects(session.presentChallenge({}), e => e.code === 'LINE_REGISTRATION_UNSUPPORTED');
  session.cancel(); account.logout();
});

test('policy is re-queried and Japan requires explicit age skip before ready', async () => {
  let agreements = [1];
  const h = harness({ talk: { getProfile: async () => ({ mid: 'new-user', regionCode: 'JP' }),
    getPendingAgreements: async () => ({ pendingAgreements: agreements }) } });
  const { account, session, states } = await start(h); await session.selectCountry('JP'); await password(session); await session.createAccount('secret');
  await session.submitPrivacy({ privacySyncContacts: false, privacySearchByPhoneNumber: false });
  assert.equal(states.at(-1).stage, 'ageVerification');
  await session.skipAgeVerification(); assert.equal(states.at(-1).stage, 'agreementRequired');
  await session.resumeFinalization(); assert.equal(account.getAccountId(), undefined);
  agreements = []; await session.resumeFinalization(); await session.result;
  assert.equal(account.getAccountId(), 'new-user'); account.logout();
});

test('locale formatter matches LINE Chinese and Indonesian locale conventions', () => {
  const h = harness(), { formatLineLocale } = h.load(base + 'network/LineLocale');
  for (const [input, region, output] of [['zh-CN', 'CN', 'zh-Hans_CN'], ['zh-Hant-TW', 'TW', 'zh-Hant_TW'],
    ['zh-Hans_CN', 'CN', 'zh-Hans_CN'], ['in-ID', 'ID', 'id_ID'], ['en-US', 'US', 'en_US']]) {
    assert.equal(formatLineLocale(input, region), output);
  }
});

test('synchronous UI cancellation at creating prevents an unsent registration RPC', async () => {
  const h = harness(), account = h.create();
  let session;
  session = account.startPhoneRegistration(state => { if (state.stage === 'creating') session.cancel(); });
  session.result.catch(() => {}); await tick(); await password(session);
  await assert.rejects(session.createAccount('secret'), { code: 'LINE_REGISTRATION_CANCELLED' });
  assert.equal(h.calls.includes('create'), false);
});

test('empty update result requires matching fetched privacy values and profile identity', async () => {
  const h = harness({ talk: { getSettings: async () => ({}) } });
  const { account, session } = await start(h); await password(session); await session.createAccount('secret');
  await assert.rejects(session.submitPrivacy({ privacySyncContacts: true, privacySearchByPhoneNumber: false }),
    { code: 'LINE_REGISTRATION_INCOMPLETE' });
  assert.equal(account.getAccountId(), undefined);
  h.talk.getSettings = async () => ({ privacySyncContacts: true, privacySearchByPhoneNumber: false });
  await session.resumeFinalization(); await session.result; assert.equal(account.getAccountId(), 'new-user');
});

test('storage migrates v1, rejects malformed v2, and expired stored ready account blocks registration without refresh', async () => {
  const h = harness(), { LineAccountStore } = h.load(base + 'auth/LineAccountStore');
  const store = new LineAccountStore({});
  const record = { version: 1, mid: 'old', accessToken: 'old', refreshToken: 'refresh', certificate: '',
    loginSessionId: '', durationUntilRefreshInSec: 600, expiresAt: Date.now() - 1 };
  h.values.set('account.v1', JSON.stringify(record));
  assert.equal(store.load().credential.role, 'SECONDARY'); assert.equal(store.load().credential.stage, 'ready');
  const { session } = await start(h);
  await assert.rejects(session.result, { code: 'LINE_REGISTRATION_ACCOUNT_CONFLICT' });
  assert.equal(h.values.get('account.v1'), JSON.stringify(record)); assert.equal(h.calls.length, 0);
  for (const patch of [{ version: 3 }, { version: 2 }, { version: 2, role: 'PRIMARY', stage: 'unknown' },
    { version: 2, role: 'PRIMARY', stage: 'pendingFinalization', registration: {} }]) {
    h.values.set('account.v1', JSON.stringify({ ...record, ...patch })); assert.equal(store.load(), undefined);
  }
});

test('pending restart expiry refreshes with primary identity and each finalizer RPC uses rotated access', async () => {
  const requests = [];
  const str = value => [Buffer.byteLength(value), ...Buffer.from(value)];
  const reply = (r, fields) => Uint8Array.from([0x82, 0x41, r.body[2], ...str(r.method), ...fields, 0]);
  let rejectProfile = true;
  const h = harness({ registration: { talkFactory: undefined }, transport: {
    applicationHeader: 'SECONDARY', applicationHeaderFor: role => role,
    send: async r => {
      requests.push(r); assert.equal(r.role, 'PRIMARY'); assert.equal(r.accessKind, 'ACCOUNT');
      if (r.method === 'reportRefreshedAccessToken') return reply(r, [12, 0, 0]);
      if (r.method === 'refresh') return reply(r, [12, 0, 0x18, ...str('rotated'), 0x16, 0xb0, 9, 0x1c, 0, 0]);
      if (r.method === 'getProfile' && rejectProfile) {
        rejectProfile = false; return reply(r, [0x1c, 0x15, 0xee, 1, 0]);
      }
      assert.equal(r.sessionAccess, 'rotated');
      switch (r.method) {
        case 'getProfile': return reply(r, [12, 0, 0x18, ...str('new-user'), 0xb8, ...str('US'), 0]);
        case 'getPendingAgreements': return reply(r, [12, 0, 0x19, 0x05, 0]);
        case 'getConfigurations': return reply(r, [12, 0, 0]);
        default: throw Error(r.method);
      }
    }
  } });
  const checkpoint = { displayName: 'User', countryCode: 'US', countrySetOfEEA: ['DE'], nameUpdated: true,
    configurationsLoaded: false, countryUpdated: false, privacyUpdated: false };
  h.values.set('account.v1', JSON.stringify({ version: 2, role: 'PRIMARY', stage: 'pendingFinalization', registration: checkpoint,
    mid: 'new-user', accessToken: 'expired', refreshToken: 'refresh', certificate: '', loginSessionId: '',
    durationUntilRefreshInSec: 600, expiresAt: Date.now() - 10 }));
  const account = h.create();
  await assert.rejects(account.restoreSession(), { code: 'LINE_REGISTRATION_INCOMPLETE' });
  assert.equal(account.getAccountId(), undefined); assert.throws(() => account.requireAccessToken(), { code: 'LINE_REGISTRATION_INCOMPLETE' });
  const states = [], session = account.startPhoneRegistration(s => states.push(s)); session.result.catch(() => {});
  await tick(); assert.equal(states.at(-1).stage, 'privacySettings');
  assert.equal(requests.filter(r => r.method === 'refresh').length, 2, 'expired token and explicit Talk119 each refresh once');
  assert.equal(JSON.parse(h.values.get('account.v1')).stage, 'pendingFinalization');
  assert.equal(h.calls.includes('open'), false); session.cancel();
});

test('country policy uses fetched profile region and preserves explicit signed refusal', async () => {
  let saved = {}, presented;
  const h = harness({ registration: { presentationFactory: () => ({ cancel() {}, presentChallenge: async () => false,
    presentAgreement: async (_context, agreements, _account, policy) => {
      presented = { agreements, policy }; return { policy, timestampMs: -1700000000123 };
    } }) }, talk: {
    getProfile: async () => ({ mid: 'new-user', regionCode: 'TH' }),
    getSettings: async () => saved,
    updateCountryAgreement: async (policy, value) => { assert.equal(policy, 'TH_PDPA'); saved.agreementPdpa = value; return []; },
    updatePrivacy: async privacy => { Object.assign(saved, privacy); return []; }
  } });
  const { account, session, states } = await start(h); await password(session); await session.createAccount('secret');
  await session.submitPrivacy({ privacySyncContacts: false, privacySearchByPhoneNumber: false });
  assert.equal(states.at(-1).stage, 'agreementRequired'); assert.equal(account.getAccountId(), undefined);
  await session.presentAgreement({}); await session.result;
  assert.deepEqual(presented, { agreements: [], policy: 'TH_PDPA' }); assert.equal(saved.agreementPdpa, -1700000000123);
});

test('ready primary identity propagates to account RPC and web headers while secondary stays unchanged', async () => {
  const requests = [];
  const h = harness({ transport: { applicationHeader: 'secondary-header', applicationHeaderFor: role => role + '-header',
    send: async r => { requests.push(r); return new Uint8Array([1]); } } });
  const { account, session } = await start(h); await password(session); await session.createAccount('secret');
  await session.submitPrivacy({ privacySyncContacts: false, privacySearchByPhoneNumber: false }); await session.result;
  assert.equal(account.getWebAuthHeaders()['X-Line-Application'], 'PRIMARY-header');
  await account.sendAccountRpc({ path: '/LIFF1', method: 'test', body: new Uint8Array() });
  assert.equal(requests[0].role, 'PRIMARY'); assert.equal(requests[0].accessKind, 'ACCOUNT');
});

test('missing primary header capability rejects before anonymous registration', async () => {
  const h = harness({ transport: { applicationHeader: 'secondary', send: async () => { throw Error('must not send'); } } });
  const { session } = await start(h);
  assert.equal(session.getState().stage, 'failed');
  await assert.rejects(session.result, { code: 'LINE_CONNECTION_CONFIG_REQUIRED' });
  assert.equal(h.calls.length, 0);
});

test('config phase tolerates only declared Thrift failure and never hides unsupported identity', async () => {
  const h = harness(), { MiniAppError } = h.load('main/ets/core/MiniAppError');
  h.talk.getConfigurations = async () => { throw new MiniAppError('LINE_REGISTRATION_APPLICATION_ERROR', 'private server message'); };
  const { session } = await start(h); await password(session); await session.createAccount('secret');
  assert.equal(session.getState().stage, 'privacySettings');
  const h2 = harness(), { MiniAppError: E } = h2.load('main/ets/core/MiniAppError');
  h2.talk.getConfigurations = async () => { throw new E('LINE_CONNECTION_CONFIG_REQUIRED', 'private configuration'); };
  const s2 = await start(h2); await password(s2.session);
  await assert.rejects(s2.session.createAccount('secret'), { code: 'LINE_CONNECTION_CONFIG_REQUIRED' });
  assert.equal(s2.account.getAccountId(), undefined);
});

test('IVR does not start SMS resend cooldown', async () => {
  const h = harness(), { session } = await start(h);
  await session.submitPhoneNumber('555'); await session.requestVerification(2);
  assert.equal(session.getState().resendRemainingMs, 0);
  await session.requestVerification(1); assert.equal(session.getState().resendRemainingMs, 60000);
});

test('initialization HUMAN keeps its session and accepted presentation requires explicit retry', async () => {
  let countryCalls = 0, shown;
  const h = harness({ registration: { presentationFactory: () => ({ cancel() {},
    presentChallenge: async (_context, details) => { shown = details; return true; },
    presentAgreement: async () => undefined }) } });
  const { LineRegistrationError } = h.load(base + 'registration/LineRegistrationError');
  h.client.getCountryInfo = async () => {
    if (++countryCalls === 1) throw new LineRegistrationError({ code: 5,
      webAuthDetails: { baseUrl: 'https://private-init', token: 'private-challenge' } });
    return { countryCode: 'US', countrySetOfEEA: [] };
  };
  const { session, account } = await start(h);
  assert.equal(session.getState().stage, 'challengeRequired');
  await assert.rejects(account.startQrLogin(() => {}), { code: 'LINE_LOGIN_IN_PROGRESS' });
  await session.presentChallenge({}); assert.equal(session.getState().stage, 'initializing');
  assert.equal(countryCalls, 1); assert.equal(shown.token, 'private-challenge');
  await session.retryInitialization(); assert.equal(session.getState().stage, 'phoneInput');
  assert.equal(h.calls.filter(call => call === 'open').length, 1);
  assert.equal(countryCalls, 2);
});

test('non-HUMAN errors carrying details never become a challenge', async () => {
  const h = harness(), { LineRegistrationError } = h.load(base + 'registration/LineRegistrationError');
  h.client.requestCode = async () => { throw new LineRegistrationError({ code: 4, webAuthDetails: { baseUrl: 'private', token: 'private' } }); };
  const { session } = await start(h); await session.submitPhoneNumber('555');
  await assert.rejects(session.requestVerification(1), e => e.code === 'LINE_REGISTRATION_RETRY_LATER' && !e.webAuthDetails);
  assert.equal(session.getState().stage, 'verification');
});

test('Japan age prompt uses selected phone country while policy uses profile region', async () => {
  const h = harness(), { session } = await start(h);
  await session.selectCountry('JP'); await password(session); await session.createAccount('secret');
  await session.submitPrivacy({ privacySyncContacts: false, privacySearchByPhoneNumber: false });
  assert.equal(session.getState().stage, 'ageVerification');
  await session.skipAgeVerification(); await session.result;
});

test('PULL message observer cancellation sends no long poll after releasing ownership', async () => {
  let polls = 0;
  const h = harness({ client: {
    fetchPullSms: async () => ({ destinationPhoneNumber: '123', pinCodeMessage: 'send this message' }),
    waitPullSms: async () => { polls++; return { accountExist: false, allowedToRegister: true }; }
  } });
  const account = h.create(); let session;
  session = account.startPhoneRegistration(state => { if (state.pinCodeMessage) session.cancel(); });
  session.result.catch(() => {}); await tick(); await session.submitPhoneNumber('555');
  await assert.rejects(session.startPullSms(), { code: 'LINE_REGISTRATION_CANCELLED' });
  assert.equal(polls, 0);
  assert.equal(await account.startQrLogin(() => {}), 'old-user');
});

test('busy observer cancellation prevents initialization preparation and action dispatch', async () => {
  const h = harness(), { LinePhoneRegistrationSession } = h.load(base + 'registration/LinePhoneRegistrationSession');
  let prepares = 0, session;
  session = new LinePhoneRegistrationSession(h.client, { hash: async () => 'hash' }, {
    assertIdentity() {}, release() {}, prepare: async () => { prepares++; return undefined; }
  }, () => session.cancel(), undefined, () => 1);
  session.result.catch(() => {}); await tick(); assert.equal(prepares, 0);
  assert.equal(session.getState().busy, false);

  const account = h.create(); let active, cancelOnBusy = false, profiles = 0;
  h.client.validateProfile = async () => { profiles++; };
  active = account.startPhoneRegistration(state => { if (cancelOnBusy && state.busy) active.cancel(); });
  active.result.catch(() => {}); await tick();
  await active.submitPhoneNumber('555'); await active.requestVerification(1); await active.verifyCode('123');
  cancelOnBusy = true;
  await assert.rejects(active.validateProfile('Name'), { code: 'LINE_REGISTRATION_CANCELLED' });
  assert.equal(profiles, 0); assert.equal(active.getState().busy, false);
});

test('stored pending checkpoints reject present null or falsy decision and privacy values', () => {
  const h = harness(), { LineAccountStore } = h.load(base + 'auth/LineAccountStore'), store = new LineAccountStore({});
  const checkpoint = { displayName: 'User', countryCode: 'TH', countrySetOfEEA: [], profileRegion: 'TH',
    nameUpdated: true, configurationsLoaded: true, countryUpdated: false, privacyUpdated: false };
  const record = { version: 2, role: 'PRIMARY', stage: 'pendingFinalization', mid: 'new-user', accessToken: 'access',
    refreshToken: 'refresh', certificate: '', loginSessionId: '', durationUntilRefreshInSec: 600, expiresAt: Date.now() + 600000 };
  const load = patch => {
    h.values.set('account.v1', JSON.stringify({ ...record, registration: { ...checkpoint, ...patch } }));
    return store.load();
  };
  assert.ok(load({}));
  for (const value of [null, false, 0, '', [], {}, { policy: 'TH_PDPA', timestampMs: 0 }]) {
    for (const done of [false, true]) {
      assert.equal(load({ countryDecision: value, countryUpdated: done }), undefined, `decision ${JSON.stringify(value)} / ${done}`);
      assert.equal(load({ privacy: value, privacyUpdated: done }), undefined, `privacy ${JSON.stringify(value)} / ${done}`);
    }
  }
  assert.equal(load({ countryUpdated: true }), undefined);
  assert.equal(load({ privacyUpdated: true }), undefined);
  assert.ok(load({ countryDecision: { policy: 'TH_PDPA', timestampMs: -1700000000123 }, countryUpdated: true,
    privacy: { privacySyncContacts: false, privacySearchByPhoneNumber: false }, privacyUpdated: true }));
});

test('finalizer requires a valid matching country decision even when completed flag is true', async () => {
  const h = harness({ talk: { getProfile: async () => ({ mid: 'new-user', regionCode: 'TH' }) } });
  const { LineRegistrationFinalizer } = h.load(base + 'registration/LineRegistrationFinalizer');
  const checkpoint = { displayName: 'User', countryCode: 'TH', countrySetOfEEA: [], nameUpdated: true,
    configurationsLoaded: true, countryUpdated: true, privacyUpdated: true,
    privacy: { privacySyncContacts: false, privacySearchByPhoneNumber: false } };
  const hooks = { talk: () => h.talk, assertProfile() {}, save() {} };
  for (const decision of [undefined, null, false, 0, '', [], {}, { policy: 'GDPR', timestampMs: 1700000000123 },
    { policy: 'TH_PDPA', timestampMs: 0 }, { policy: 'TH_PDPA', timestampMs: 1.5 }]) {
    const finalizer = new LineRegistrationFinalizer({ ...checkpoint, countryDecision: decision }, hooks, () => {});
    assert.equal(await finalizer.resume(), 'agreementRequired', JSON.stringify(decision));
  }
  const completed = new LineRegistrationFinalizer({ ...checkpoint,
    countryDecision: { policy: 'TH_PDPA', timestampMs: -1700000000123 } }, hooks, () => {});
  assert.equal(await completed.resume(), 'ready');
  assert.equal(h.calls.filter(call => Array.isArray(call) && call[0] === 'country').length, 0);

  let acceptedTimestamp;
  h.talk.updateCountryAgreement = async (_policy, timestamp) => { acceptedTimestamp = timestamp; return []; };
  h.talk.getSettings = async () => ({ agreementPdpa: acceptedTimestamp });
  const repaired = new LineRegistrationFinalizer({ ...checkpoint, countryDecision: null }, hooks, () => {});
  assert.equal(await repaired.resume(), 'agreementRequired');
  repaired.recordAgreement({ policy: 'TH_PDPA', timestampMs: 1700000000123 });
  assert.equal(await repaired.resume(), 'ready');
  assert.equal(acceptedTimestamp, 1700000000123, 'new explicit choice must not inherit the corrupt completed flag');
});

test('initialization retry rejects cancellation from its busy observer without another country request', async () => {
  let calls = 0, cancelOnBusy = false, session;
  const h = harness({ registration: { presentationFactory: () => ({ cancel() {}, presentChallenge: async () => true,
    presentAgreement: async () => undefined }) } });
  const { LineRegistrationError } = h.load(base + 'registration/LineRegistrationError');
  h.client.getCountryInfo = async () => {
    calls++;
    throw new LineRegistrationError({ code: 5, webAuthDetails: { baseUrl: 'https://private', token: 'private' } });
  };
  session = h.create().startPhoneRegistration(state => { if (cancelOnBusy && state.busy) session.cancel(); });
  session.result.catch(() => {}); await tick(); await session.presentChallenge({});
  cancelOnBusy = true;
  await assert.rejects(session.retryInitialization(), { code: 'LINE_REGISTRATION_CANCELLED' });
  assert.equal(calls, 1); assert.equal(session.getState().busy, false);
});

test('immediate initialization retry cannot race the scheduled initial session open', async () => {
  const h = harness(), session = h.create().startPhoneRegistration(() => {});
  session.result.catch(() => {});
  await assert.rejects(session.retryInitialization(), { code: 'LINE_REGISTRATION_INVALID_STATE' });
  await tick();
  assert.equal(h.calls.filter(call => call === 'open').length, 1);
  assert.equal(session.getState().stage, 'phoneInput');
});

for (const method of [1, 2]) {
  test(`failed PULL wait can recover to usable ${method === 1 ? 'SMS' : 'IVR'} code entry`, async () => {
    let verified;
    const h = harness({ client: {
      fetchPullSms: async () => ({ destinationPhoneNumber: '+1555000', pinCodeMessage: 'exact outbound message' }),
      waitPullSms: async () => { throw Error('wait failed'); },
      verifyCode: async request => { verified = request; return { accountExist: false, allowedToRegister: true }; }
    } });
    const { session } = await start(h);
    await session.submitPhoneNumber('555');
    await assert.rejects(session.startPullSms(), { code: 'LINE_REGISTRATION_FAILED' });
    assert.equal(session.getState().destinationPhoneNumber, '+1555000');
    assert.equal(session.getState().pinCodeMessage, 'exact outbound message');
    await session.requestVerification(method);
    const state = session.getState();
    assert.equal(state.stage, 'verification'); assert.equal(state.busy, false);
    assert.equal(state.destinationPhoneNumber, undefined); assert.equal(state.pinCodeMessage, undefined);
    assert.equal(state.errorCode, undefined);
    assert.equal(state.resendRemainingMs, method === 1 ? 60000 : 0);
    await session.verifyCode('private-pin');
    assert.equal(verified.pinCode, 'private-pin'); assert.equal(session.getState().stage, 'profileInput');
    assert.ok(!JSON.stringify(session.getState()).includes('private-pin'));
  });
}

for (const change of ['phone', 'country']) {
  test(`changing ${change} clears invalidated PULL instructions and verification ownership`, async () => {
    const h = harness({ client: {
      fetchPullSms: async () => ({ destinationPhoneNumber: '+1555000', pinCodeMessage: 'outbound message' }),
      waitPullSms: async () => { throw Error('wait failed'); }
    } });
    const { session } = await start(h);
    await session.submitPhoneNumber('555'); await session.requestVerification(1);
    await assert.rejects(session.startPullSms());
    if (change === 'phone') await session.submitPhoneNumber('777');
    else await session.selectCountry('JP');
    const state = session.getState();
    assert.equal(state.destinationPhoneNumber, undefined); assert.equal(state.pinCodeMessage, undefined);
    assert.equal(state.resendRemainingMs, 0);
    assert.equal(state.stage, change === 'phone' ? 'verification' : 'phoneInput');
    await assert.rejects(session.verifyCode('old-pin'));
  });
}

