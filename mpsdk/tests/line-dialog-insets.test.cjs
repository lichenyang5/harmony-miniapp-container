const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./sdk-loader.cjs');

function fixture() {
  const AvoidAreaType = { TYPE_SYSTEM: 0, TYPE_CUTOUT: 1, TYPE_NAVIGATION_INDICATOR: 4 };
  const load = createLoader(undefined, undefined, { AvoidAreaType });
  return load('main/ets/vendors/line/LineDialogInsets').readLineDialogInsets;
}

function area(top, right, bottom, left) {
  return { topRect: { height: top }, rightRect: { width: right },
    bottomRect: { height: bottom }, leftRect: { width: left } };
}

test('LINE fullscreen dialog combines system, cutout and navigation insets in vp without double-counting', () => {
  const read = fixture();
  let areas = new Map([[0, area(96, 0, 0, 0)], [1, area(120, 24, 0, 0)], [4, area(0, 0, 72, 0)]]);
  const hostWindow = { getWindowAvoidArea: type => areas.get(type) };
  assert.deepEqual(read(hostWindow, px => px / 3), { top: 40, right: 8, bottom: 24, left: 0 });
  areas = new Map([[0, area(0, 0, 0, 0)], [1, area(0, 0, 0, 96)], [4, area(0, 0, 18, 0)]]);
  assert.deepEqual(read(hostWindow, px => px / 3), { top: 0, right: 0, bottom: 6, left: 32 });
});

test('unavailable navigation inset does not discard the valid status-bar inset', () => {
  const read = fixture();
  const hostWindow = { getWindowAvoidArea(type) {
    if (type !== 0) throw new Error('not supported');
    return area(80, 0, 0, 0);
  } };
  assert.deepEqual(read(hostWindow, px => px / 2), { top: 40, right: 0, bottom: 0, left: 0 });
});
