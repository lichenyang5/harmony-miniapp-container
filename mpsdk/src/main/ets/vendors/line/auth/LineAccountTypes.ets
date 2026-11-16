import { LineClientRole } from '../network/LineTransport';
import { LineRegistrationCheckpoint } from '../registration/LineRegistrationSessionTypes';
import { common } from '@kit.AbilityKit';

/** X25519 原始公钥与私钥均为 32 字节；不含 DER/SPKI 包装。 */
export const LINE_X25519_KEY_BYTES: number = 32;

/** 扫码内部兼容名称；邮箱和扫码使用相同的 X25519 原始密钥格式。 */
export const LINE_QR_KEY_BYTES: number = LINE_X25519_KEY_BYTES;

export interface LineQrCodeResponse {
  callbackUrl: string;
  longPollingMaxCount: number;
  longPollingIntervalSec: number;
  nonce: string;
}

export interface LineQrLoginRequest {
  authSessionId: string;
  systemName: string;
  modelName: string;
  autoLoginIsRequired: boolean;
  nonce: string;
}

/** 内部账号凭据；不可作为宿主 UI 状态或网页桥数据导出。 */
export interface LineAccountCredential {
  role?: LineClientRole;
  stage?: 'ready' | 'pendingFinalization';
  registration?: LineRegistrationCheckpoint;
  certificate: string;
  accessToken: string;
  refreshToken: string;
  mid: string;
  loginSessionId: string;
  durationUntilRefreshInSec: number;
  metaData: Map<string, string>;
}

export interface LineRefreshTokenResult {
  accessToken: string;
  refreshToken?: string;
  durationUntilRefreshInSec: number;
}

export interface LineQrKeyPair {
  publicKey: Uint8Array;
  privateKey: Uint8Array;
}

export interface LineQrKeySource {
  create(): Promise<LineQrKeyPair>;
}

export interface LineQrLoginState {
  kind: 'qrReady' | 'qrVerified' | 'pinReady' | 'authorized';
  url?: string;
  pin?: string;
  mid?: string;
}

export interface LineQrLoginRunner {
  login(systemName: string, modelName: string,
    onState: (state: LineQrLoginState) => void): Promise<LineAccountCredential>;

  cancel(): void;
}


/** 创建时明确选择存储策略，避免恢复操作悄悄改变后续登录行为。 */
export interface LineAccountOptions {
  persistent?: boolean;

  /** 系统 Preferences 使用宿主应用上下文；不保存页面或 WebView 引用。 */
  storageContext?: common.Context;
}
