/** 官方子视图展示模式；缺省或未知值由展示层回退到 FULL。 */
export enum LineSubViewPresentationType {
  FULL = 1,
  TALL = 2,
  COMPACT = 3
}

/** 官方子视图关闭入口位置；缺省或未知值由展示层回退到 RIGHT。 */
export enum LineSubViewCloseButtonPosition {
  RIGHT = 1,
  LEFT = 2
}

export interface LineSubViewPresentation {
  presentationType?: LineSubViewPresentationType;
  closeButtonPosition?: LineSubViewCloseButtonPosition;
  closeButtonLabel?: string;
  hideCloseButton?: boolean;
}
