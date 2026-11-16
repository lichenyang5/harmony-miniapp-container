import { webview } from '@kit.ArkWeb';

/** 新窗口事件的同步快照，不持有 ArkWeb handler。 */
export interface WebNewWindowRequest {
  readonly url: string;
  readonly isUserTrigger: boolean;
  readonly isAlert: boolean;
  readonly documentId: number;
}

/** 同步预留原生窗口；Web 层确认控制器后才展示。 */
export interface WebNewWindow {
  readonly controller: webview.WebviewController;
  /** 单次展示；绑定控制器失败时不调用。 */
  show: () => Promise<void>;
  /** 幂等取消，覆盖尚未展示和正在挂载的窗口。 */
  close: () => void;
}
