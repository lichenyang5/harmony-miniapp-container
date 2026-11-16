import { LineMode } from "./LineMode";

/** 当前容器的 LIFF 协议身份与 featureToken；由发行结果或 app 命令建立，不代表原生账号状态。 */
export interface LineAppState {
  readonly liffId: string;
  readonly featureToken: string;
  readonly lineMode?: LineMode;
}

/** Bridge 读取当前凭据；其他模块通过会话的 LineAdapter 查询真实 LIFF ID。 */
export interface LineAppStateProvider {
  /** 尚未建立 LIFF 状态或容器已释放时返回 undefined。 */
  getAppState(): LineAppState | undefined;
}
