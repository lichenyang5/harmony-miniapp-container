const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('required initialization runs before host script without restoring overridden vendor scripts', () => {
  const config = createLoader()('main/ets/web/MiniAppWebConfig');
  const vendor = [
    { script: 'init()', scriptRules: ['*'], required: true },
    { script: 'vendor()', scriptRules: ['vendor'] }
  ];
  const info = { appId: 'app', vendor: 'line', url: 'https://example.com', jsOnDocStart: 'host()' };
  assert.deepEqual(config.mergeDocumentStartScripts(vendor, info), [
    { script: 'init()', scriptRules: ['*'] }, { script: 'host()', scriptRules: ['*'] }
  ]);
  assert.equal(config.mergeDocumentStartScripts(vendor, { ...info, jsOnDocStart: '' }).length, 2);
});

test('MiniApp Web config uses the configured start script instead of vendor scripts', () => {
  const load = createLoader();
  const config = load('main/ets/web/MiniAppWebConfig');
  const vendor = [{ script: 'vendor()', scriptRules: ['vendor'] }];
  const info = {
    appId: 'app', vendor: 'vk', url: 'https://example.com', jsOnDocStart: 'host()',
    jsOnDocStartRules: [], jsOnDocEnd: 'end()', extraUserAgentParams: {
      ' channel ': ' mini ', blank: ' '
    }
  };
  const start = config.mergeDocumentStartScripts(vendor, info);
  assert.deepEqual(start, [
    { script: 'host()', scriptRules: ['*'] }
  ]);
  assert.deepEqual(config.documentEndScripts(info), [{ script: 'end()', scriptRules: ['*'] }]);
  assert.equal(config.resolveUserAgent('base', info), 'base channel/mini');
  assert.equal(info.extraUserAgentParams[' channel '], ' mini ');
});

test('MiniApp Web config falls back to vendor scripts when the configured start script is blank', () => {
  const load = createLoader();
  const config = load('main/ets/web/MiniAppWebConfig');
  const vendor = [{ script: 'vendor()', scriptRules: ['vendor'] }];
  const info = { appId: 'app', vendor: 'vk', url: 'https://example.com', jsOnDocStart: ' ', customUserAgent: ' Agent ' };
  const start = config.mergeDocumentStartScripts(vendor, info);
  vendor[0].scriptRules[0] = 'changed';
  assert.deepEqual(start, [{ script: 'vendor()', scriptRules: ['vendor'] }]);
  assert.equal(config.resolveUserAgent('base', info), 'Agent');
});
