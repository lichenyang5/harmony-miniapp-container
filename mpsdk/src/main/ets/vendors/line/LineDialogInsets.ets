import { window } from '@kit.ArkUI';

export interface LineDialogInsets {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

/** LINE 弹层按宿主窗口的真实避让区布局；系统数据为 px，组件 padding 为 vp。 */
export function readLineDialogInsets(hostWindow: window.Window,
  pxToVp: (value: number) => number): LineDialogInsets {
  const result: LineDialogInsets = {
    top: 0,
    right: 0,
    bottom: 0,
    left: 0
  };
  const types: window.AvoidAreaType[] = [window.AvoidAreaType.TYPE_SYSTEM,
    window.AvoidAreaType.TYPE_CUTOUT, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR];
  types.forEach((type: window.AvoidAreaType): void => {
    try {
      const area: window.AvoidArea = hostWindow.getWindowAvoidArea(type);
      result.top = Math.max(result.top, pxToVp(area.topRect.height));
      result.right = Math.max(result.right, pxToVp(area.rightRect.width));
      result.bottom = Math.max(result.bottom, pxToVp(area.bottomRect.height));
      result.left = Math.max(result.left, pxToVp(area.leftRect.width));
    } catch (_) { /* 单种避让区不可用时，保留其他系统区域；不猜测固定状态栏高度。 */
    }
  });
  return result;
}
