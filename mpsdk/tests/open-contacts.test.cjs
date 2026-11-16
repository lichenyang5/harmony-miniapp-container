const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');
const { createTestSession } = require('./test-session.cjs');
const { applicationLifecycle } = require('./application-lifecycle.cjs');

async function flush() { for (let i = 0; i < 30; i++) await Promise.resolve(); }

function fixture(selectContacts, sharedLoad, host) {
  const calls = [];
  const contact = { selectContacts(options) {
    calls.push(options);
    return selectContacts ? selectContacts(options) : Promise.resolve([]);
  } };
  const load = sharedLoad || createLoader({}, {}, undefined, contact);
  const lifecycle = applicationLifecycle(load);
  const sent = [];
  const context = createTestSession(load, { id: 'contacts', host,
    onScript(script) {
      new Function('window', script)({ atomicBridge: { postResponse(id, event) { sent.push({ id, event }); } } });
    }
  });
  const binding = context.getBinding();
  return { load, lifecycle, binding, context, sent, calls,
    request(params = { request_id: 42 }) {
      return binding.injections[0].object.onInterceptRequest(JSON.stringify({
        type: 'vk-connect', handler: 'VKWebAppOpenContacts', params
      }), 'original-route');
    },
    close() { context.close(); lifecycle.onAbilityDestroy({ context: context.uiAbilityContext }); }
  };
}

test('open contacts registers and returns the first raw number through the real proxy', async () => {
  const f = fixture(async () => [{
    name: { givenName: 'Ada', familyName: 'Lovelace', fullName: 'Ada Lovelace' },
    phoneNumbers: [{ phoneNumber: ' +1 555 0100 ' }, { phoneNumber: 'second' }]
  }, {
    name: { fullName: 'Second' }, phoneNumbers: [{ phoneNumber: 'second-contact' }]
  }]);
  f.lifecycle.onAbilityCreate({ context: f.context.uiAbilityContext });
  f.lifecycle.onAbilityForeground({ context: f.context.uiAbilityContext });
  try {
    assert.equal(f.request().intercept, true);
    await flush();
    assert.deepEqual(f.calls, [{ isMultiSelect: false, maxSelectable: 1, isDisplayedByName: false }]);
    assert.deepEqual(f.sent, [{ id: 'original-route', event: {
      type: 'VKWebAppOpenContactsResult',
      data: { phone: ' +1 555 0100 ', first_name: 'Ada', last_name: 'Lovelace', request_id: 42 }
    } }]);
  } finally { f.close(); }
});

test('display name fallback and empty name keep the official three fields', async () => {
  let selected = [{ name: { fullName: 'Single Display Name' }, phoneNumbers: [{ phoneNumber: '123' }] }];
  const f = fixture(async () => selected);
  const host = f.context.uiAbilityContext;
  f.lifecycle.onAbilityCreate({ context: host });
  f.lifecycle.onAbilityForeground({ context: host });
  try {
    f.request(); await flush();
    assert.deepEqual(f.sent.pop().event.data, { phone: '123', first_name: 'Single Display Name',
      last_name: '', request_id: 42 });
    selected = [{ name: { givenName: 'Ada', fullName: 'Ada Lovelace' },
      phoneNumbers: [{ phoneNumber: '456' }] }];
    f.request(); await flush();
    assert.deepEqual(f.sent.pop().event.data, { phone: '456', first_name: 'Ada', last_name: '', request_id: 42 });
  } finally { f.close(); }
});

test('empty selection maps to user denial; invalid data and native rejection are unknown', async () => {
  let outcome = [];
  const f = fixture(async () => {
    if (outcome instanceof Error) throw outcome;
    return outcome;
  });
  const host = f.context.uiAbilityContext;
  f.lifecycle.onAbilityCreate({ context: host });
  f.lifecycle.onAbilityForeground({ context: host });
  try {
    for (const [value, code] of [
      [[], 4], [[{ name: { fullName: 'No Number' } }], 1],
      [[{ phoneNumbers: [{ phoneNumber: 3 }, { phoneNumber: 'valid later' }] }], 1],
      [new Error('private native error'), 1]
    ]) {
      outcome = value;
      f.request(); await flush();
      const response = f.sent.pop();
      assert.equal(response.id, 'original-route');
      assert.equal(response.event.type, 'VKWebAppOpenContactsFailed');
      assert.equal(response.event.data.request_id, 42);
      assert.equal(response.event.data.error_data.error_code, code);
      assert.equal(JSON.stringify(response).includes('private native error'), false);
    }
  } finally { f.close(); }
});

test('handler maps unsupported to client 6 and invalid object shape to client 5', async () => {
  let calls = 0;
  const load = createLoader({}, {}, undefined, { selectContacts() { calls++; return Promise.resolve([]); } },
    () => false);
  const f = fixture(undefined, load);
  const { VkUsersHandler } = f.load('main/ets/vendors/vk/handlers/VkUserInfoHandler');
  const { VkAdapter } = f.load('main/ets/vendors/vk/VkAdapter');
  const handler = new VkUsersHandler(f.context, new VkAdapter());
  try {
    await assert.rejects(handler.openContacts([]), error => error.code === 'INVALID_ARGUMENT');
    assert.equal(calls, 0);
    await assert.rejects(handler.openContacts({}), error => error.toData().error_data.error_code === 6);
    assert.equal(calls, 0);
  } finally { handler.dispose(); f.close(); }
});

test('background and absent lifecycle block the system picker', async () => {
  const f = fixture(async () => [{ phoneNumbers: [{ phoneNumber: '123' }] }]);
  const host = f.context.uiAbilityContext;
  try {
    f.request(); await flush();
    assert.equal(f.sent.pop().event.data.error_data.error_code, 1);
    f.lifecycle.onAbilityCreate({ context: host });
    f.request(); await flush();
    assert.equal(f.sent.pop().event.data.error_data.error_code, 9);
    assert.equal(f.calls.length, 0);
    f.lifecycle.onAbilityForeground({ context: host });
    f.request(); await flush();
    assert.equal(f.sent.pop().event.data.phone, '123');
  } finally { f.close(); }
});

test('invalid native name fields cannot enter the VK success envelope', async () => {
  const f = fixture(async () => [{ name: { givenName: 9, fullName: 'Valid' },
    phoneNumbers: [{ phoneNumber: '123' }] }]);
  const host = f.context.uiAbilityContext;
  f.lifecycle.onAbilityCreate({ context: host });
  f.lifecycle.onAbilityForeground({ context: host });
  try {
    f.request(); await flush();
    assert.equal(f.sent.pop().event.data.error_data.error_code, 1);
  } finally { f.close(); }
});

test('native picker occupancy outlives page cleanup and late result is dropped', async () => {
  let finish;
  const f = fixture(() => new Promise(resolve => { finish = resolve; }));
  const host = f.context.uiAbilityContext;
  f.lifecycle.onAbilityCreate({ context: host });
  f.lifecycle.onAbilityForeground({ context: host });
  try {
    assert.equal(f.request().timeout, -1);
    await flush();
    f.request(); await flush();
    assert.equal(f.sent.pop().event.data.error_data.error_code, 1);
    assert.equal(f.calls.length, 1);
    f.context.beginDocument('https://vk.ru/app1?next');
    f.request(); await flush();
    assert.equal(f.sent.pop().event.data.error_data.error_code, 1);
    finish([{ phoneNumbers: [{ phoneNumber: 'late' }] }]);
    await flush();
    assert.equal(f.sent.length, 0);
    f.request(); await flush();
    assert.equal(f.calls.length, 2);
  } finally { f.close(); }
});

test('same app id sessions share only their host occupancy', async () => {
  const finish = [];
  const select = () => new Promise(resolve => { finish.push(resolve); });
  const a = fixture(select);
  const sameHost = fixture(undefined, a.load, a.context.uiAbilityContext);
  const otherHost = fixture(undefined, a.load);
  const hostA = a.context.uiAbilityContext, hostB = otherHost.context.uiAbilityContext;
  a.lifecycle.onAbilityCreate({ context: hostA });
  a.lifecycle.onAbilityForeground({ context: hostA });
  a.lifecycle.onAbilityCreate({ context: hostB });
  a.lifecycle.onAbilityForeground({ context: hostB });
  try {
    a.request(); await flush();
    sameHost.request(); await flush();
    assert.equal(sameHost.sent.pop().event.data.error_data.error_code, 1);
    otherHost.request(); await flush();
    assert.equal(finish.length, 2);
    finish[1]([{ phoneNumbers: [{ phoneNumber: 'host-b' }] }]);
    await flush();
    assert.equal(otherHost.sent.pop().event.data.phone, 'host-b');
    a.context.close();
    sameHost.request(); await flush();
    assert.equal(sameHost.sent.pop().event.data.error_data.error_code, 1);
    finish[0]([{ phoneNumbers: [{ phoneNumber: 'late-a' }] }]);
    await flush();
    assert.equal(a.sent.length, 0);
    const retry = sameHost.request(); await flush();
    assert.equal(retry.intercept, true);
    assert.equal(finish.length, 3);
    finish[2]([{ phoneNumbers: [{ phoneNumber: 'host-a' }] }]);
    await flush();
    assert.equal(sameHost.sent.pop().event.data.phone, 'host-a');
  } finally {
    a.context.close(); sameHost.context.close(); otherHost.context.close();
    a.lifecycle.onAbilityDestroy({ context: hostA });
    a.lifecycle.onAbilityDestroy({ context: hostB });
  }
});

test('malformed params pass through at protocol boundary without invoking picker', async () => {
  const f = fixture(async () => [{ phoneNumbers: [{ phoneNumber: '123' }] }]);
  const host = f.context.uiAbilityContext;
  f.lifecycle.onAbilityCreate({ context: host });
  f.lifecycle.onAbilityForeground({ context: host });
  try {
    assert.equal(f.request([]).intercept, false);
    assert.equal(f.request(null).intercept, false);
    await flush();
    assert.equal(f.calls.length, 0);
    assert.equal(f.sent.length, 0);
  } finally { f.close(); }
});
