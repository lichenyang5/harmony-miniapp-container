const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');
const tick = () => new Promise(resolve => setImmediate(resolve));

function fixture({ dial = async () => {}, mail = async (_type, _params, callback) => callback.onResult({}),
  sms = async () => {}, foreground = true, windowLookup } = {}) {
  const calls = [], failures = [], logs = [];
  const context = { async startAbilityByType(type, params, callback) {
    calls.push({ type, params }); return mail(type, params, callback);
  }, async startAbilityForResult(want) { calls.push(want); return sms(); } };
  const load = createLoader(undefined, undefined, {
    async getLastWindow() { if (windowLookup) await windowLookup(); return { getUIContext: () => ({ getPromptAction: () => ({
      showToast: options => failures.push(options.message.name)
    }) }) }; }
  }, undefined, undefined, undefined, {
    '@kit.TelephonyKit': { call: { async makeCall(host, number) { calls.push({ host, number }); return dial(); } } }
  });
  const { MiniAppSDK } = load('main/ets/core/MiniAppSDK');
  let lifecycle;
  MiniAppSDK.initialize({ on(_event, callback) { lifecycle = callback; return 1; } });
  const ability = { context };
  lifecycle.onAbilityCreate(ability);
  if (foreground) lifecycle.onAbilityForeground(ability);
  const { SdkLogger } = load('main/ets/logging/SdkLogger');
  SdkLogger.install({ write(level, event, details) { logs.push({ level, event, ...JSON.parse(details) }); } });
  SdkLogger.setLevel(0);
  const { SystemLinkTools } = load('main/ets/capabilities/links/SystemLinkTools');
  const { WebSystemSchemeHandler } = load('main/ets/web/scheme/WebSystemSchemeHandler');
  const { WebSchemeDispatcher } = load('main/ets/web/scheme/WebSchemeDispatcher');
  const { WebSchemeDecision: D } = load('main/ets/web/scheme/WebSchemeTypes');
  const handler = new WebSystemSchemeHandler(context);
  const dispatcher = new WebSchemeDispatcher([handler]);
  return { tools: new SystemLinkTools(context), handler, dispatcher, calls, failures, logs, D,
    background() { lifecycle.onAbilityBackground(ability); },
    dispatch(url, isMainFrame = true) { return dispatcher.dispatch({ url, isMainFrame }); } };
}

test('exact schemes match case insensitively and unrelated schemes continue through the chain', () => {
  const f = fixture();
  for (const url of ['tel:+123', 'MAILTO:a@example.test', 'sms:123']) {
    assert.equal(f.handler.supports({ url }), true);
  }
  for (const url of ['telephone:123', 'https://example.test', 'line://app/id', ' mailto:a@b', 'telx', 'mailtoX', 'smsX']) {
    assert.equal(f.dispatch(url), f.D.PASS);
  }
});

test('telephone opens the dial screen preserving the international number as a string', async () => {
  const f = fixture();
  assert.equal(f.dispatch('TEL:%2B81-090-1234'), f.D.CONSUME);
  await tick();
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].number, '+81-090-1234');
});

test('mailto decodes once and maps only supported fields using the mail panel encoding', async () => {
  const f = fixture();
  await f.tools.open('mailto:a+tag@example.test,b@example.test?subject=%E4%B8%AD%E6%96%87%2520&body=a%0Ab%2Bc&cc=c@example.test&bcc=d@example.test&bundleName=evil&stream=file:///secret');
  assert.deepEqual(f.calls, [{ type: 'mail', params: {
    email: ['a+tag@example.test', 'b@example.test'], cc: ['c@example.test'], bcc: ['d@example.test'],
    subject: encodeURI('中文%20'), body: encodeURI('a\nb+c')
  } }]);
});

test('mailto query recipients are combined with path recipients rather than silently dropped', async () => {
  const f = fixture();
  await f.tools.open('mailto:path@example.test?to=first%2Btag@example.test&to=second@example.test');
  assert.deepEqual(f.calls[0].params.email, ['path@example.test', 'first+tag@example.test', 'second@example.test']);
  await f.tools.open('mailto:?to=only@example.test');
  assert.deepEqual(f.calls[1].params.email, ['only@example.test']);
  await assert.rejects(f.tools.open('mailto:?to=a%0D%0Ab'), { code: 'INVALID_ARGUMENT' });
});

test('empty mail recipient is allowed but malformed escaping and recipient header injection are rejected', async () => {
  const f = fixture();
  await f.tools.open('mailto:?subject=hello+world');
  assert.equal(f.calls[0].params.subject, 'hello+world');
  for (const url of ['tel:', 'tel:%ZZ', 'tel:123?evil=1', 'tel:123%0A456',
    'mailto:a%0D%0ABcc:evil@example.test', 'mailto:a@b?cc=x%0Ay', 'mailto:a@b?subject=%ZZ',
    'mailto:a@b?subject=a%0D%0Ab', 'mailto://a@b']) {
    await assert.rejects(f.tools.open(url), { code: 'INVALID_ARGUMENT' }, url);
  }
});

test('a missing scheme separator never starts a system operation', async () => {
  const f = fixture();
  await assert.rejects(f.tools.open('tel1'), { code: 'NOT_SUPPORTED' });
  assert.deepEqual(f.calls, []);
});

test('sms opens a system editor with string recipients and decoded body without sending directly', async () => {
  const f = fixture();
  assert.equal(f.dispatch('SMS:%2B8190,00123?body=%E4%B8%AD%E6%96%87%0Aa%2Bb&bundleName=evil'), f.D.CONSUME);
  await tick();
  assert.equal(f.calls[0].bundleName, 'com.ohos.mms');
  assert.equal(f.calls[0].abilityName, 'com.ohos.mms.MainAbility');
  assert.equal(f.calls[0].parameters.pageFlag, 'conversation');
  assert.deepEqual(JSON.parse(f.calls[0].parameters.contactObjects), [
    { contactsName: '', telephone: '+8190' }, { contactsName: '', telephone: '00123' }
  ]);
  assert.equal(f.calls[0].parameters.content, '中文\na+b');
  assert.deepEqual(f.failures, []);
  for (const url of ['sms:123%0A456', 'sms:abc', 'sms:123?body=%ZZ']) {
    await assert.rejects(f.tools.open(url), { code: 'INVALID_ARGUMENT' });
  }
});

test('subframes, disposed handlers and background hosts cannot start system UI', async () => {
  const f = fixture();
  assert.equal(f.dispatch('tel:123', false), f.D.BLOCK);
  f.dispatcher.dispose(); assert.equal(f.dispatch('tel:123'), f.D.BLOCK);
  assert.deepEqual(f.calls, []);
  const b = fixture({ foreground: false });
  await assert.rejects(b.tools.open('tel:123'), { code: 'APP_IN_BACKGROUND' });
  await assert.rejects(b.tools.open('mailto:a@b'), { code: 'APP_IN_BACKGROUND' });
  await assert.rejects(b.tools.open('sms:123'), { code: 'APP_IN_BACKGROUND' });
  assert.deepEqual(b.calls, []);
});

test('a rejected SMS editor launch is reported as a platform failure, not unsupported', async () => {
  const f = fixture({ sms: async () => { throw Error('platform rejected'); } });
  f.dispatch('sms:123'); await tick();
  assert.deepEqual(f.failures, ['app.string.mp_web_system_link_failed']);
});

test('an external panel without a completion callback does not lock later system links', async () => {
  let callback;
  const f = fixture({ mail: async (_type, _params, cb) => { callback = cb; } });
  assert.equal(f.dispatch('mailto:a@b'), f.D.CONSUME); await tick();
  assert.equal(f.dispatch('tel:123'), f.D.CONSUME);
  assert.equal(f.dispatch('sms:456'), f.D.CONSUME); await tick();
  assert.equal(f.calls.length, 3);
  assert.ok(f.logs.some(log => log.event === 'WebSystemScheme.received' && log.level === 1));
  callback.onResult({}); await tick();
});

test('an unresolved dial request does not lock another number or another system scheme', async () => {
  const callbacks = [];
  const f = fixture({ dial: () => new Promise(resolve => callbacks.push(resolve)) });
  assert.equal(f.dispatch('tel:123'), f.D.CONSUME);
  assert.equal(f.dispatch('tel:456'), f.D.CONSUME);
  assert.equal(f.dispatch('sms:789'), f.D.CONSUME);
  assert.equal(f.calls.length, 3);
  callbacks.forEach(resolve => resolve()); await tick();
});

test('reset and disposal discard late errors without blocking subsequent requests', async () => {
  let reject;
  const f = fixture({ dial: () => new Promise((_resolve, fail) => { reject = fail; }) });
  f.dispatch('tel:123');
  f.dispatcher.reset(); reject(Error('old')); await tick();
  assert.deepEqual(f.failures, []);
  f.dispatch('tel:123'); reject(Error('current')); await tick();
  assert.deepEqual(f.failures, ['app.string.mp_web_system_link_failed']);
  f.dispatch('tel:123'); f.dispatcher.dispose(); reject(Error('closed')); await tick();
  assert.equal(f.failures.length, 1);
});

test('dial logs include request, startup, completion and the original platform rejection code', async () => {
  const f = fixture();
  await f.tools.open('tel:123');
  assert.ok(f.logs.some(log => log.event === 'SystemLink.request' && log.data === 'tel:123'));
  assert.ok(f.logs.some(log => log.event === 'SystemLink.openStarted' && log.capability === 'tel'));
  assert.ok(f.logs.some(log => log.event === 'SystemLink.openCompleted' && log.capability === 'tel'));
  const rejected = fixture({ dial: async () => { throw Object.assign(new Error('native dial rejected'), { code: 8300002 }); } });
  await assert.rejects(rejected.tools.open('tel:123'), { code: 'SYSTEM_ERROR' });
  assert.ok(rejected.logs.some(log => log.event === 'SystemLink.openFailed' && log.code === '8300002'));
  assert.ok(rejected.logs.some(log => log.event === 'SystemLink.failureDetail' && log.data.includes('native dial rejected')));
});
test('mail late onError is observed and duplicate platform completion settles only once', async () => {
  let callback;
  const f = fixture({ mail: async (_type, _params, cb) => { callback = cb; } });
  f.dispatch('mailto:a@b'); await tick();
  assert.equal(f.dispatch('tel:123'), f.D.CONSUME);
  callback.onError(123, 'failure', 'private message');
  callback.onError(456, 'duplicate', 'private message'); callback.onResult({}); await tick();
  assert.deepEqual(f.failures, ['app.string.mp_web_system_link_failed']);
});

test('failure notification after an asynchronous window lookup is discarded for replaced pages', async () => {
  let resolveWindow;
  const f = fixture({ dial: async () => { throw Error('failure'); },
    windowLookup: () => new Promise(resolve => { resolveWindow = resolve; }) });
  f.dispatch('tel:123'); await tick();
  assert.equal(typeof resolveWindow, 'function');
  f.dispatcher.reset(); resolveWindow(); await tick();
  assert.deepEqual(f.failures, []);
});

test('failure prompt errors are logged at the async boundary instead of being silently swallowed', async () => {
  const f = fixture({ dial: async () => { throw Error('dial failure'); },
    windowLookup: async () => { throw Error('window unavailable'); } });
  f.dispatch('tel:123'); await tick();
  assert.ok(f.logs.some(log => log.event === 'WebSystemScheme.failurePromptFailed'));
  assert.deepEqual(f.failures, []);
});

test('synchronous mail startup exceptions and rejected startup promises are reported without unhandled rejections', async () => {
  for (const mail of [() => { throw Error('sync'); }, async () => { throw Error('async'); }]) {
    const f = fixture({ mail });
    f.dispatch('mailto:a@b'); await tick();
    assert.deepEqual(f.failures, ['app.string.mp_web_system_link_failed']);
  }
});
