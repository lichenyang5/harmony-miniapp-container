const test = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');

function setup() {
  const load = createLoader();
  return {
    ...load('main/ets/web/scheme/WebSchemeDispatcher'),
    ...load('main/ets/web/scheme/WebSchemeTypes'),
    ...load('main/ets/web/scheme/WebSchemeErrorCode'),
    ...load('main/ets/core/MiniAppError'),
    ...load('main/ets/logging/SdkLogger')
  };
}
const request = (url = 'demo://anything') => ({ url, isMainFrame: true });
const handler = (id, handle, extra = {}) => ({ id, supports: request => /^demo:/i.test(request.url), handle, ...extra });

test('an empty registration list passes requests; non-array registration is a stable error', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D, MiniAppError, WebSchemeErrorCode: E } = setup();
  assert.equal(new WebSchemeDispatcher([]).dispatch(request()), D.PASS);
  for (const invalid of [null, undefined, {}, 'demo']) {
    assert.throws(() => new WebSchemeDispatcher(invalid),
      error => error instanceof MiniAppError && error.code === E.INVALID_REGISTRATION);
  }
});

test('ordinary WebView requests need no document or session and preserve the original URL', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  let received;
  const dispatcher = new WebSchemeDispatcher([handler('ordinary', value => { received = value; return D.CONSUME; })]);
  const input = request('DeMo:opaque/path?secret=1');
  assert.equal(dispatcher.dispatch(input), D.CONSUME);
  assert.equal(received, input);
  for (const url of ['', ' demo:x', '\ndemo:x', '1demo:x', 'démo:x', '//demo:x', 'demo/path', 'other:x']) {
    assert.equal(dispatcher.dispatch(request(url)), D.PASS, url);
  }
});

test('one interceptor can support several protocols and match host or path', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  const dispatcher = new WebSchemeDispatcher([handler('links', () => D.CONSUME, {
    supports: request => /^https?:\/\/example\.com\/app(?:[/?#]|$)/i.test(request.url)
  })]);
  for (const url of ['http://example.com/app', 'HTTPS://example.com/app?id=1']) {
    assert.equal(dispatcher.dispatch(request(url)), D.CONSUME);
  }
  for (const url of ['https://other.com/app', 'https://example.com/ordinary', 'demo:app']) {
    assert.equal(dispatcher.dispatch(request(url)), D.PASS);
  }
});

test('supported handlers explicitly proceed in registration order and return the downstream result', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  for (const stop of [D.CONSUME, D.BLOCK, D.PASS]) {
    const calls = [];
    const dispatcher = new WebSchemeDispatcher([
      handler('unrelated', () => assert.fail('unsupported handler must not run'), { supports: () => false }),
      handler('first', (request, chain) => { calls.push(1); return chain.proceed(); }),
      handler('second', (request, chain) => { calls.push(2); return stop === D.PASS ? chain.proceed() : stop; }),
      handler('third', (request, chain) => { calls.push(3); return chain.proceed(); })
    ]);
    assert.equal(dispatcher.dispatch(request()), stop);
    assert.deepEqual(calls, stop === D.PASS ? [1, 2, 3] : [1, 2]);
  }
});

test('registration uses a snapshot of the input list', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  let disposed = 0;
  const items = [handler('first', () => D.CONSUME, { dispose: () => disposed++ })];
  const dispatcher = new WebSchemeDispatcher(items);
  items.splice(0, 1, handler('replacement', () => D.BLOCK));
  assert.equal(dispatcher.dispatch(request()), D.CONSUME);
  dispatcher.dispose();
  assert.equal(disposed, 1);
});

test('invalid registrations fail atomically and clean the entire batch once per instance', () => {
  const { WebSchemeDispatcher, MiniAppError, WebSchemeErrorCode: E } = setup();
  for (const invalid of [
    { id: '', supports() { return true; }, handle() {} },
    { id: 'bad', handle() {} },
    { id: 'bad', supports: true, handle() {} },
    { id: 'bad', supports() { return true; }, handle: null },
    { id: 'bad', supports() { return true; }, handle() {}, reset: true },
    { id: 'bad', supports() { return true; }, handle() {}, dispose: true },
    null
  ]) {
    const released = [];
    const first = handler('first', () => { throw Error('registration must not dispatch'); }, {
      dispose() { released.push('first'); throw Error('private failure'); }
    });
    const last = handler('last', () => {}, { dispose() { released.push('last'); } });
    assert.throws(() => new WebSchemeDispatcher([first, invalid, last, first]),
      error => error instanceof MiniAppError && error.code === E.INVALID_REGISTRATION);
    assert.deepEqual(released, ['first', 'last']);
  }
});

test('duplicate ids fail even with different matching rules and release both handler instances', () => {
  const { WebSchemeDispatcher, WebSchemeErrorCode: E } = setup();
  let released = 0;
  assert.throws(() => new WebSchemeDispatcher([
    handler('same', () => {}, { dispose() { released++; } }),
    handler('same', () => {}, { supports: () => false, dispose() { released++; } })
  ]), error => error.code === E.INVALID_REGISTRATION);
  assert.equal(released, 2);
});

test('handler ids are stable diagnostic tokens without URL, whitespace or trailing newline', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D, WebSchemeErrorCode: E } = setup();
  for (const id of ['https://private.example/token', 'bad id', 'bad\tid', 'bad\nid', 'bad\n', 'bad\r', 'é']) {
    assert.throws(() => new WebSchemeDispatcher([handler(id, () => D.PASS)]), error => error.code === E.INVALID_REGISTRATION, id);
  }
  const dispatcher = new WebSchemeDispatcher([handler('Line.liff_command-1', () => D.CONSUME)]);
  assert.equal(dispatcher.dispatch(request()), D.CONSUME);
});

test('failed-batch cleanup does not reread an invalid id getter and continues after dispose failure', () => {
  const { WebSchemeDispatcher, WebSchemeErrorCode: E, SdkLogger } = setup();
  const logs = [];
  SdkLogger.install({ write(level, event, details) { logs.push(details); } });
  let disposed = 0;
  const invalid = {
    get id() { throw Error('private id getter'); },
    supports: () => true,
    handle() {},
    dispose() { disposed++; throw Error('private dispose'); }
  };
  const last = handler('last', () => {}, { dispose() { disposed++; } });
  assert.throws(() => new WebSchemeDispatcher([invalid, last]), error => error.code === E.INVALID_REGISTRATION);
  assert.equal(disposed, 2);
  assert.doesNotMatch(JSON.stringify(logs), /private|getter/);
});

test('a rejected Promise decision blocks and consumes the rejection without leaking its cause', async () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D, SdkLogger } = setup();
  const logs = [];
  SdkLogger.install({ write(level, event, details) { logs.push(details); } });
  const dispatcher = new WebSchemeDispatcher([
    handler('async-handler', () => Promise.reject(Error('private rejection payload'))),
    handler('later', () => assert.fail('invalid decision must stop'))
  ]);
  assert.equal(dispatcher.dispatch(request()), D.BLOCK);
  await new Promise(resolve => setImmediate(resolve));
  assert.doesNotMatch(JSON.stringify(logs), /private|payload/);
});

test('exceptions and invalid or asynchronous decisions BLOCK and never reach later handlers', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D, SdkLogger } = setup();
  const logs = [];
  SdkLogger.install({ write(level, event, details) { logs.push({ level, event, details }); } });
  for (const result of [undefined, null, true, 'PASS', 999, Promise.resolve(D.PASS)]) {
    const dispatcher = new WebSchemeDispatcher([
      handler('bad-result', () => result), handler('later', () => assert.fail('must stop'))
    ]);
    assert.equal(dispatcher.dispatch(request()), D.BLOCK);
  }
  const dispatcher = new WebSchemeDispatcher([handler('throwing', () => { throw Error('private secret payload'); })]);
  assert.equal(dispatcher.dispatch(request('demo:secret-url')), D.BLOCK);
  assert.ok(logs.length > 0);
  assert.doesNotMatch(JSON.stringify(logs), /secret|payload|demo:/);
});

test('reset retains registrations and isolates reset failures; dispose is idempotent', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  const calls = [];
  const dispatcher = new WebSchemeDispatcher([
    handler('first', (request, chain) => chain.proceed(), {
      reset() { calls.push('reset-first'); throw Error('private'); },
      dispose() { calls.push('dispose-first'); throw Error('private'); }
    }),
    handler('second', () => D.CONSUME, {
      reset() { calls.push('reset-second'); }, dispose() { calls.push('dispose-second'); }
    })
  ]);
  dispatcher.reset();
  assert.equal(dispatcher.dispatch(request()), D.CONSUME);
  dispatcher.dispose();
  dispatcher.dispose();
  dispatcher.reset();
  assert.equal(dispatcher.dispatch(request()), D.BLOCK);
  assert.equal(dispatcher.dispatch(request('unknown:x')), D.BLOCK);
  assert.deepEqual(calls, ['reset-first', 'reset-second', 'dispose-first', 'dispose-second']);
});

for (const action of ['reset', 'dispose']) {
  for (const resultName of ['PASS', 'CONSUME', 'BLOCK']) {
    test(`${action} inside handle invalidates the current ${resultName} decision`, () => {
      const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
      let dispatcher;
      dispatcher = new WebSchemeDispatcher([
        handler('reentrant', () => { dispatcher[action](); return D[resultName]; }),
        handler('later', () => assert.fail('stale request must stop'))
      ]);
      assert.equal(dispatcher.dispatch(request()), D.BLOCK);
    });
  }
}

test('lifecycle hooks may reenter reset/dispose without recursion or repeated release', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  let dispatcher;
  let resets = 0;
  let releases = 0;
  dispatcher = new WebSchemeDispatcher([handler('reentrant', () => D.PASS, {
    reset() { resets++; dispatcher.reset(); },
    dispose() { releases++; dispatcher.dispose(); }
  })]);
  dispatcher.reset();
  dispatcher.dispose();
  assert.equal(resets, 1);
  assert.equal(releases, 1);
});

test('dispose inside reset stops later reset hooks and blocks navigation during cleanup', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  const calls = [];
  let dispatcher;
  dispatcher = new WebSchemeDispatcher([
    handler('first', () => assert.fail('cleanup must block dispatch'), {
      reset() {
        assert.equal(dispatcher.dispatch(request()), D.BLOCK);
        dispatcher.dispose();
      },
      dispose() { calls.push('first'); }
    }),
    handler('second', () => D.PASS, {
      reset() { assert.fail('disposed handler must not reset'); },
      dispose() { calls.push('second'); }
    })
  ]);
  dispatcher.reset();
  assert.deepEqual(calls, ['first', 'second']);
});

test('matching failures and non-boolean or async results block without reaching handle', async () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D, SdkLogger } = setup();
  const logs = [];
  SdkLogger.install({ write(level, event, details) { logs.push(details); } });
  const matchers = [
    () => { throw Error('private matcher failure'); },
    ...[undefined, null, 1, 'true', Promise.resolve(true)].map(value => () => value),
    () => Promise.reject(Error('private matcher rejection'))
  ];
  for (const supports of matchers) {
    const dispatcher = new WebSchemeDispatcher([
      handler('invalid', () => assert.fail('invalid matcher must stop'), { supports }),
      handler('later', () => assert.fail('later handler must not run'))
    ]);
    assert.equal(dispatcher.dispatch(request()), D.BLOCK);
  }
  await new Promise(resolve => setImmediate(resolve));
  assert.doesNotMatch(JSON.stringify(logs), /private|rejection|failure/);
});

for (const action of ['reset', 'dispose']) {
  for (const supported of [true, false]) {
    test(`${action} inside supports blocks before handle even when matching returns ${supported}`, () => {
      const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
      let dispatcher;
      dispatcher = new WebSchemeDispatcher([
        handler('reentrant-match', () => assert.fail('stale matcher must not handle'), {
          supports() { dispatcher[action](); return supported; }
        }),
        handler('later', () => assert.fail('stale matching must stop'))
      ]);
      assert.equal(dispatcher.dispatch(request()), D.BLOCK);
    });
  }
}


test('returning PASS does not implicitly execute the downstream chain', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  let later = 0;
  const dispatcher = new WebSchemeDispatcher([
    handler('terminal', () => D.PASS),
    handler('later', () => { later++; return D.CONSUME; })
  ]);
  assert.equal(dispatcher.dispatch(request()), D.PASS);
  assert.equal(later, 0);
});

test('chain end returns PASS exactly once and unwinds through upstream handlers', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  const calls = [];
  const input = request();
  const dispatcher = new WebSchemeDispatcher([
    handler('outer', (received, chain) => {
      assert.equal(received, input); calls.push('outer.before');
      const result = chain.proceed(); calls.push('outer.after'); return result;
    }),
    handler('skip', () => assert.fail('unsupported'), { supports: () => false }),
    handler('inner', (received, chain) => {
      assert.equal(received, input); calls.push('inner'); return chain.proceed();
    })
  ]);
  assert.equal(dispatcher.dispatch(input), D.PASS);
  assert.deepEqual(calls, ['outer.before', 'inner', 'outer.after']);
});

test('duplicate proceed blocks and does not execute downstream twice', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  let calls = 0;
  const dispatcher = new WebSchemeDispatcher([
    handler('twice', (request, chain) => {
      assert.equal(chain.proceed(), D.CONSUME);
      assert.equal(chain.proceed(), D.BLOCK);
      return D.CONSUME;
    }),
    handler('later', () => { calls++; return D.CONSUME; })
  ]);
  assert.equal(dispatcher.dispatch(request()), D.BLOCK);
  assert.equal(calls, 1);
});

test('saved chains cannot proceed after handle returns, throws or rejects asynchronously', async () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  for (const finish of [() => D.CONSUME, () => { throw Error('private'); }, () => Promise.reject(Error('private'))]) {
    let saved;
    let later = 0;
    const dispatcher = new WebSchemeDispatcher([
      handler('save', (request, chain) => { saved = chain; return finish(); }),
      handler('later', () => { later++; return D.CONSUME; })
    ]);
    dispatcher.dispatch(request());
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(saved.proceed(), D.BLOCK);
    assert.equal(later, 0);
  }
});

for (const action of ['reset', 'dispose']) {
  test(`${action} before or inside proceed invalidates the entire call chain`, () => {
    const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
    for (const position of ['before', 'inside']) {
      let calls = 0;
      let dispatcher;
      dispatcher = new WebSchemeDispatcher([
        handler('outer', (request, chain) => {
          if (position === 'before') dispatcher[action]();
          const result = chain.proceed();
          assert.equal(result, D.BLOCK);
          return D.CONSUME;
        }),
        handler('inner', () => { calls++; dispatcher[action](); return D.CONSUME; })
      ]);
      assert.equal(dispatcher.dispatch(request()), D.BLOCK);
      assert.equal(calls, position === 'before' ? 0 : 1);
    }
  });
}

test('separate dispatches have independent chains and a stale chain cannot enter a new request', () => {
  const { WebSchemeDispatcher, WebSchemeDecision: D } = setup();
  let saved;
  const calls = [];
  const dispatcher = new WebSchemeDispatcher([
    handler('outer', (request, chain) => { saved = chain; return chain.proceed(); }),
    handler('inner', request => { calls.push(request.url); return D.CONSUME; })
  ]);
  assert.equal(dispatcher.dispatch(request('demo:first')), D.CONSUME);
  const first = saved;
  dispatcher.reset();
  assert.equal(dispatcher.dispatch(request('demo:second')), D.CONSUME);
  assert.equal(first.proceed(), D.BLOCK);
  assert.equal(saved.proceed(), D.BLOCK);
  assert.deepEqual(calls, ['demo:first', 'demo:second']);
});
