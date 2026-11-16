const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const file = path.join(__dirname, '../entry/src/main/ets/model/MiniAppCatalog.ets');
const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const exported = {};
new Function('exports', output)(exported);
const { parseCatalog, createLaunchInfo } = exported;
const entries = JSON.parse(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/resources/rawfile/miniapps.json'), 'utf8'));

test('catalog supplies one valid entry for each selected vendor', () => {
  assert.deepEqual(parseCatalog(JSON.stringify(entries)), entries);
  assert.deepEqual(new Set(entries.map(app => app.vendor)), new Set(['line', 'vk']));
});

test('catalog rejects malformed, duplicate and mismatched vendor URLs', () => {
  for (const content of ['null', '{}', '[]', '[null]', '[1]', '"text"']) {
    assert.throws(() => parseCatalog(content));
  }
  assert.throws(() => parseCatalog(JSON.stringify([entries[0], entries[0]])));
  for (const url of ['http://vk.ru/app54769936', 'https://vk.ru.evil.example/app54769936',
    'https://user@vk.ru/app54769936', 'https://vk.ru/app1', 'javascript:alert(1)']) {
    assert.throws(() => parseCatalog(JSON.stringify([{ ...entries[1], url }])));
  }
});

test('launch mapping excludes injected scripts, credentials and insecure overrides', () => {
  const actual = createLaunchInfo({ ...entries[0], jsOnDocStart: 'untrusted()',
    jsOnDocEnd: 'untrusted()', isSSLIgnore: true, token: 'private' });
  assert.deepEqual(actual, { appId: entries[0].appId, vendor: 'line', url: entries[0].url,
    isSSLIgnore: false, isOpenGeolocation: false });
});
