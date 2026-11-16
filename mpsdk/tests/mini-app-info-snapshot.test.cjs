const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('MiniAppInfo snapshot copies supported fields and mutable values', () => {
  const load = createLoader();
  const { snapshotMiniAppInfo } = load('main/ets/core/MiniAppInfoSnapshot');
  const source = {
    appId: 'app', vendor: 'vk', url: 'https://backend.example/app', customUserAgent: 'Agent',
    extraUserAgentParams: { channel: 'first' }, isSyncLoad: true, isOpenDomStorage: false,
    isOpenGeolocation: false, isOpenNewWindow: true, jsOnDocStart: 'start()',
    jsOnDocStartRules: ['start'], jsOnDocEnd: 'end()', jsOnDocEndRules: ['end'], isSSLIgnore: true
  };
  const first = snapshotMiniAppInfo(source);
  const sibling = snapshotMiniAppInfo(source);
  source.extraUserAgentParams.channel = 'source';
  source.jsOnDocStartRules[0] = 'source';
  sibling.extraUserAgentParams.channel = 'sibling';
  sibling.jsOnDocEndRules[0] = 'sibling';
  assert.deepEqual(first, {
    appId: 'app', vendor: 'vk', url: 'https://backend.example/app', customUserAgent: 'Agent',
    extraUserAgentParams: { channel: 'first' }, isSyncLoad: true, isOpenDomStorage: false,
    isOpenGeolocation: false, isOpenNewWindow: true, jsOnDocStart: 'start()',
    jsOnDocStartRules: ['start'], jsOnDocEnd: 'end()', jsOnDocEndRules: ['end'], isSSLIgnore: true
  });
});
