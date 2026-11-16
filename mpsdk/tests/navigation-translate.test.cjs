const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createLoader } = require('./sdk-loader.cjs');

test('translation command is unavailable before the WebView navigation endpoint attaches', async () => {
  const load = createLoader();
  const { MiniAppNavigationController } = load('main/ets/web/MiniAppNavigationController');
  const navigation = new MiniAppNavigationController();

  assert.equal(await navigation.translatePage(), false);
});

test('translation command sends the requested translate.js setup to the attached session', async () => {
  const load = createLoader();
  const { MiniAppNavigationController } = load('main/ets/web/MiniAppNavigationController');
  const navigation = new MiniAppNavigationController();
  const scripts = [];
  navigation.attach({ session: { async send(script) { scripts.push(script); return true; } } });

  assert.equal(await navigation.translatePage(), true);
  assert.equal(scripts.length, 1);
  assert.match(scripts[0], /https:\/\/cdn\.staticfile\.net\/translate\.js\/3\.18\.75\/translate\.js/);
  assert.match(scripts[0], /translate\.language\.setLocal\('russian'\)/);
  assert.match(scripts[0], /translate\.service\.use\('client\.edge'\)/);
  assert.match(scripts[0], /translate\.execute\(\)/);
  assert.match(scripts[0], /getElementById\(scriptId\)/);
});
