import { LineAccountCredential } from './LineAccountTypes';

/** PIN/E2EE 的 AES 字节块长度，协议校验与加密实现共用。 */
export const LINE_EMAIL_AES_BLOCK_BYTES: number = 16;

/** LoginType / LoginResultType，数字值沿用 APK Thrift enum。 */
export enum LineEmailLoginType {
  ID_CREDENTIAL = 0,
  /** PIN/E2EE 验证后，APK continueLoginAfterPinVerification 使用该类型完成认证。 */
  QRCODE = 1,
  ID_CREDENTIAL_WITH_E2EE = 2
}

export enum LineEmailResultType {
  SUCCESS = 1,
  QR = 2,
  DEVICE = 3,
  SMS = 4
}

/** AuthService RSA 参数；sessionKey 只供原生加密密码，不向 UI 或网页交付。 */
export interface LineEmailRsaKey {
  keynm: string;
  nvalue: string;
  evalue: string;
  sessionKey: string;
}

/** password 已经是 RSA 加密后的十六进制；这里不接收或保存明文密码。 */
export interface LineEmailLoginRequest {
  type: number;
  keynm: string;
  password: string;
  systemName: string;
  modelName: string;
  certificate?: string;
  verifier?: string;
  secret?: Uint8Array;
  e2eeVersion: number;
}

export interface LineEmailLoginResult {
  type: number;
  verifier?: string;
  pin?: string;
  credential?: LineAccountCredential;
}

/** JSON 只解码服务器公钥和密钥链；证明计算、解密和私钥生命周期属于 Crypto。 */
export interface LineEmailVerification {
  kind: 'verifier' | 'e2ee' | 'cancel';
  verifier?: string;
  publicKey?: Uint8Array;
  encryptedKeyChain?: Uint8Array;
}

export interface LineEmailLoginState {
  kind: 'authenticating' | 'pinReady' | 'waitingForConfirmation' | 'authorized';
  pin?: string;
  mid?: string;
}

export interface LineEmailLoginRunner {
  login(email: string, password: string, systemName: string, modelName: string,
    onState: (state: LineEmailLoginState) => void): Promise<LineAccountCredential>;

  cancel(): void;
}
