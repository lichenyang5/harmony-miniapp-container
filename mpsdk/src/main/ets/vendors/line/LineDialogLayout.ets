import { LineDialogInsets } from './LineDialogInsets';
import { LineSubViewPresentationType } from './liff/LineSubViewPresentation';

const LINE_DIALOG_COMPACT_RATIO: number = 0.5;
const LINE_DIALOG_TALL_RATIO: number = 0.8;
const LINE_DIALOG_TOP_CORNER_RADIUS: number = 12;

export const LINE_DIALOG_CLOSE_HEIGHT: number = 50;
export const LINE_DIALOG_CLOSE_ICON_SIZE: number = 24;
export const LINE_DIALOG_CLOSE_ICON_MARGIN: number = 12;
export const LINE_DIALOG_CLOSE_LABEL_MARGIN: number = 16;
export const LINE_DIALOG_CLOSE_FONT_SIZE: string = '17fp';

export interface LineDialogLayout {
  width: number;
  height: number;
  topCornerRadius: number;
}

/** 输入与输出均为 vp；横屏铺满高度，圆角仍由展示模式决定，待 APK 运行比对。 */
export function computeLineDialogLayout(viewportWidth: number, viewportHeight: number,
  insets: LineDialogInsets, presentationType?: LineSubViewPresentationType): LineDialogLayout {
  const width = Math.max(0, viewportWidth - insets.left - insets.right);
  const height = Math.max(0, viewportHeight - insets.top - insets.bottom);
  let ratio: number = 1;
  let topCornerRadius: number = 0;
  if (presentationType === LineSubViewPresentationType.COMPACT) {
    ratio = LINE_DIALOG_COMPACT_RATIO;
    topCornerRadius = LINE_DIALOG_TOP_CORNER_RADIUS;
  } else if (presentationType === LineSubViewPresentationType.TALL) {
    ratio = LINE_DIALOG_TALL_RATIO;
    topCornerRadius = LINE_DIALOG_TOP_CORNER_RADIUS;
  }
  if (viewportWidth > viewportHeight) {
    ratio = 1;
  }
  return { width, height: height * ratio, topCornerRadius };
}
