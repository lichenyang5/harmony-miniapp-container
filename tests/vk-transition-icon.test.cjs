const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const exported = {};
new Function('exports', ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/model/VkTransitionIcon.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText)(exported);
const image = 'data:image/png;base64,dGVzdA==';

function fixture({ hostname = 'vk.ru', pathname = '/app54769936', iframe = false, nodes } = {}) {
  let update, hidden;
  let disconnected = false;
  const window = { innerWidth: 400, innerHeight: 800,
    addEventListener: (event, fn) => { if (event === 'pagehide') hidden = fn; }, removeEventListener() {} };
  window.top = iframe ? {} : window;
  const list = nodes || [node()];
  vm.runInNewContext(exported.vkTransitionIcon('54769936', image), {
    window, location: { protocol: 'https:', hostname, pathname, port: '' },
    console: { debug() {} },
    document: { querySelectorAll: () => list, addEventListener() {}, removeEventListener() {} },
    MutationObserver: class { constructor(fn) { update = fn; } observe() {} disconnect() { disconnected = true; } },
    getComputedStyle: () => ({ backgroundImage: 'url(original.png)' })
  });
  return { nodes: list, update: () => update?.(), hide: () => hidden?.(), disconnected: () => disconnected };
}
function node(left = 152, top = 352, tagName = 'IMG') {
  const attrs = { src: 'original.png', srcset: 'original@2x.png 2x' };
  return { tagName, style: {}, attrs,
    getBoundingClientRect: () => ({ left, top, width: 96, height: 96 }),
    getAttribute: name => attrs[name], setAttribute: (name, value) => { attrs[name] = value; },
    removeAttribute: name => { delete attrs[name]; } };
}
test('replaces the centered VK splash image while preserving its box', () => {
  const f = fixture();
  assert.equal(f.nodes[0].attrs.src, image);
  assert.equal(f.nodes[0].attrs.srcset, undefined);
  assert.equal(f.nodes[0].style.objectFit, 'contain');
});
test('unrelated pages, lookalike hosts, app IDs and business iframes remain unchanged', () => {
  for (const options of [{ hostname: 'vk.ru.example.com' }, { pathname: '/login' },
    { pathname: '/app1' }, { iframe: true }, { nodes: [node(0, 0)] }]) {
    assert.equal(fixture(options).nodes[0].attrs.src, 'original.png');
  }
});
test('ambiguous layouts remain unchanged and late elements are handled until page exit', () => {
  const ambiguous = fixture({ nodes: [node(), node()] });
  assert.equal(ambiguous.nodes[0].attrs.src, 'original.png');
  const f = fixture({ nodes: [] });
  f.nodes.push(node()); f.update();
  assert.equal(f.nodes[0].attrs.src, image);
  f.hide(); assert.equal(f.disconnected(), true);
  f.nodes.push(node()); f.update();
  assert.equal(f.nodes[1].attrs.src, 'original.png');
});
test('supports background-image splash nodes and validates native configuration', () => {
  const f = fixture({ nodes: [node(152, 352, 'DIV')] });
  assert.ok(f.nodes[0].style.backgroundImage.includes(image));
  assert.throws(() => exported.vkTransitionIcon('unsafe', image));
  assert.throws(() => exported.vkTransitionIcon('54769936', 'https://example.com/icon.png'));
});
