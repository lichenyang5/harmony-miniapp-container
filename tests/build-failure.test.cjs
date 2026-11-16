const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

test('failed HAR bootstrap restores packaged manifest in an isolated checkout', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'miniapp-build-test-'));
  try {
    for (const directory of ['tools', 'entry', 'libs', 'studio/tools/ohpm/bin']) {
      fs.mkdirSync(path.join(root, directory), { recursive: true });
    }
    for (const file of ['build.ps1', 'sdk-dependency.cjs']) {
      fs.copyFileSync(path.join(__dirname, '../tools', file), path.join(root, 'tools', file));
    }
    const manifest = { name: 'entry', dependencies: { mpsdk: 'file:../libs/mpsdk.har' } };
    fs.writeFileSync(path.join(root, 'entry/oh-package.json5'), JSON.stringify(manifest));
    fs.writeFileSync(path.join(root, 'libs/mpsdk.har'), 'test-only placeholder');
    fs.writeFileSync(path.join(root, 'studio/tools/ohpm/bin/ohpm.bat'), '@echo off\r\nexit /b 9\r\n');
    const result = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass',
      '-File', path.join(root, 'tools/build.ps1'), '-Task', 'Har', '-StudioHome', path.join(root, 'studio')],
    { encoding: 'utf8', timeout: 20000 });
    assert.ifError(result.error);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Dependency sync failed/);
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root, 'entry/oh-package.json5'), 'utf8')), manifest);
  } finally {
    // Only the exact mkdtemp-owned fixture is removed.
    fs.rmSync(root, { recursive: true, force: true });
  }
});
