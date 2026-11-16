const { createLoader } = require('../sdk-loader.cjs');
const { reply } = require('./line-web-login-rpc.cjs');
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject }; };
function fixture(source = 'liff') {
  class PlatformURL extends URL { get params() { return this.searchParams; } }
  const load = createLoader(undefined, undefined, undefined, undefined, undefined, undefined,
    { '@kit.ArkTS': { url: { URL: PlatformURL }, util: { generateRandomUUID: () => 'uuid-', TextEncoder: class { encodeInto(input) { return new TextEncoder().encode(input); } }, TextDecoder: { create: (encoding, options) => ({ decodeToString: bytes => new TextDecoder(encoding, options).decode(bytes) }) } } } });
  const { LineWebLoginSchemeHandler } = load('main/ets/vendors/line/scheme/LineWebLoginSchemeHandler');
  const { WebSchemeDispatcher } = load('main/ets/web/scheme/WebSchemeDispatcher');
  const { MiniAppError } = load('main/ets/core/MiniAppError');
  const { setLineWebLoginParameters } = load('main/ets/vendors/line/weblogin/LineWebLoginUrl');
  const { LineCompactReader } = load('main/ets/vendors/line/network/LineCompactCodec');
  const results = [], calls = [], pages = [], resumed = [], failures = [], listeners = new Set();
  let version = 1, document = 1, active = true, foreground = true;
  const account = { getVersion: () => version, requireAccessToken: () => 'native-token',
    getWebAuthHeaders: () => ({ 'X-Line-Access': 'native-token' }),
    addInvalidationListener: listener => listeners.add(listener), removeInvalidationListener: listener => listeners.delete(listener),
    sendAccountRpc: async request => {
      const reader = new LineCompactReader(request.body);
      reader.byte(); reader.byte(); const sequenceId = reader.uint(); reader.string(); reader.byte(); reader.byte(); const hookedFullUrl = reader.string(); const sessionString = reader.byte() === 0x18 ? reader.string() : undefined;
      calls.push({ ...request, input: { hookedFullUrl, sessionString }, allowed: !request.method.includes('Disallowed') });
      const result = await results.shift();
      if (result instanceof Error) throw result;
      if (!result) throw Error('Missing fixture reply');
      return reply(source, request.method, sequenceId, result);
    }, refreshRejectedToken: async () => { throw Error('Unexpected refresh'); } };
  const target = { getDocumentId: () => document, isCurrent: id => active && id === document,
    prepare: (address, allowed, id) => {
      const final = source === 'liff' && allowed ? setLineWebLoginParameters(address, { mst_challenge: 'prepared' }) : address;
      return { url: final, load: async () => resumed.push([final, id, allowed]) };
    } };
  const presenter = { request(page) { const d = deferred(); pages.push({ ...d, page });
    return { result: d.promise, cancel: () => d.reject(new MiniAppError('LINE_CONSENT_CANCELLED', 'cancelled')) }; } };
  const { LineAdapter } = load('main/ets/vendors/line/LineAdapter');
  const host = { mode: 'client', account };
  const adapter = new LineAdapter(host);
  const lifecycle = { isForeground: () => foreground };
  const appState = { current: { liffId: 'app', featureToken: 'feature' } };
  const session = { vendorId: 'line', getAdapter: () => adapter, lifecycle,
    getBinding: () => ({ getAppState: () => appState.current }) };
  const handler = new LineWebLoginSchemeHandler({ source, session: source === 'liff' ? session : undefined,
    window: target, consent: presenter,
    adapter, lifecycle, onFailure: error => failures.push(error) });
  const dispatcher = new WebSchemeDispatcher([handler]);
  const url = 'https://access.line.me/oauth2/v2.1/login?returnUri=%2Fa%3Fstate%3Dx%252By#/';
  return { handler, dispatcher, results, calls, pages, resumed, failures, listeners, account, host, url, appState,
    dispatch: (address = url) => dispatcher.dispatch({ url: address, isMainFrame: true }),
    invalidate() { version++; for (const listener of listeners) listener(); },
    replaceAccount() { host.account = { ...account }; }, background() { foreground = false; },
    navigate() { document++; dispatcher.reset(); }, deactivate() { active = false; } };
}
module.exports = { fixture, tick, deferred };
