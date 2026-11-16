import { MiniAppError } from '../../../core/MiniAppError';
import { SdkLogger } from '../../../logging/SdkLogger';
import { LineErrorCode, LineServiceErrorCode } from '../LineErrorCode';
import { LineTransport } from '../network/LineTransport';
import { LineRpcPath, LineRpcTimeout } from '../network/LineRpcConstants';
import { LineAccountCredential } from './LineAccountTypes';
import { LineEmailLoginCodec as Codec } from './LineEmailLoginCodec';
import { LineEmailE2eeMaterial, LineEmailLoginCrypto } from './LineEmailLoginCrypto';
import {
  LineEmailLoginRequest,
  LineEmailLoginResult,
  LineEmailLoginRunner,
  LineEmailLoginState,
  LineEmailLoginType,
  LineEmailResultType
} from './LineEmailLoginTypes';

/** APK SecondaryDeviceLoginBridgeImpl.k() 的 E2EE 版本。 */
const EMAIL_E2EE_VERSION: number = 1;

/** 一次认证拥有自己的明文输入和密钥；取消时立即释放引用，迟到结果仍受代次检查。 */
class EmailAttempt {
  email: string;
  password: string;
  material?: LineEmailE2eeMaterial;
  readonly cancelled: Promise<never>;
  private rejectCancellation?: (reason: MiniAppError) => void;

  constructor(email: string, password: string) {
    this.email = email;
    this.password = password;
    this.cancelled = new Promise<never>((_resolve, reject): void => {
      this.rejectCancellation = reject;
    });
  }

  clear(): void {
    this.email = '';
    this.password = '';
    this.material?.privateKey.fill(0);
    this.material?.publicKey.fill(0);
    this.material?.secret.fill(0);
  }

  cancel(): void {
    this.clear();
    this.rejectCancellation?.(new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE 邮箱登录已取消'));
  }
}

/** 邮箱认证仅返回最终凭据；账号发布、存储与 LIFF 发行由管理器负责。 */
export class LineEmailLoginClient implements LineEmailLoginRunner {
  private readonly transport: LineTransport;
  private readonly crypto: LineEmailLoginCrypto;
  private generation: number = 0;
  private sequence: number = 0;
  private attempt?: EmailAttempt;

  constructor(transport: LineTransport, crypto: LineEmailLoginCrypto) {
    this.transport = transport;
    this.crypto = crypto;
  }

  cancel(): void {
    this.generation++;
    this.attempt?.cancel();
    this.attempt = undefined;
  }

  async login(email: string, password: string, systemName: string, modelName: string,
    onState: (state: LineEmailLoginState) => void): Promise<LineAccountCredential> {
    if (typeof email !== 'string' || !email || typeof password !== 'string' || !password) {
      throw new MiniAppError(LineErrorCode.EMAIL_INVALID_ARGUMENT, '请输入 LINE 邮箱和密码');
    }
    if (!systemName || !modelName) {
      throw new MiniAppError(LineErrorCode.LOGIN_INVALID_DEVICE, 'LINE 登录缺少设备信息');
    }
    this.cancel();
    const generation: number = this.generation;
    const attempt = new EmailAttempt(email, password);
    this.attempt = attempt;
    email = '';
    password = '';
    try {
      const result = this.run(attempt, generation, systemName, modelName, onState);
      return await Promise.race([result, attempt.cancelled]);
    } catch (error) {
      const failure = MiniAppError.from(error as Object, LineErrorCode.EMAIL_LOGIN_FAILED, 'LINE 邮箱登录失败');
      if (failure.code !== LineErrorCode.LOGIN_CANCELLED) {
        SdkLogger.warn('LineEmailLogin', 'failed', { code: failure.code });
      }
      throw failure;
    } finally {
      attempt.clear();
      if (this.attempt === attempt) {
        this.attempt = undefined;
      }
    }
  }

  private async run(attempt: EmailAttempt, generation: number, systemName: string, modelName: string,
    onState: (state: LineEmailLoginState) => void): Promise<LineAccountCredential> {
    onState({ kind: 'authenticating' });
    this.assertCurrent(generation);
    const pin: string = this.crypto.createPin();
    attempt.material = await this.crypto.createE2ee(pin);
    // 生成密钥期间也可能已取消；必须在检查前拿到所有权，以便 finally 清理迟到密钥。
    try {
      this.assertCurrent(generation);
      let type: LineEmailLoginType = LineEmailLoginType.ID_CREDENTIAL_WITH_E2EE;
      let result: LineEmailLoginResult;
      try {
        result = await this.authenticate(attempt, generation, systemName, modelName, type);
      } catch (error) {
        const failure = MiniAppError.from(error as Object, LineErrorCode.EMAIL_LOGIN_FAILED, 'LINE 邮箱登录失败');
        if (failure.code !==
          LineErrorCode.emailService(LineServiceErrorCode.EMAIL_E2EE_SENDER_NOT_ALLOWED)) {
          throw failure;
        }
        this.assertCurrent(generation);
        // APK 唯一明确允许的重试：放弃 E2EE 材料并以普通身份凭据再认证一次。
        attempt.material.privateKey.fill(0);
        attempt.material.secret.fill(0);
        attempt.material = undefined;
        type = LineEmailLoginType.ID_CREDENTIAL;
        result = await this.authenticate(attempt, generation, systemName, modelName, type);
      }
      if (result.credential) {
        return result.credential;
      }
      if (result.type !== LineEmailResultType.DEVICE || !result.verifier) {
        throw new MiniAppError(LineErrorCode.EMAIL_VERIFICATION_UNSUPPORTED, 'LINE 要求其他登录验证方式');
      }
      const displayedPin: string = result.pin || (attempt.material ? pin : '');
      onState(displayedPin ? { kind: 'pinReady', pin: displayedPin } : { kind: 'waitingForConfirmation' });
      this.assertCurrent(generation);
      const bytes = await this.call('verifyEmailPin', attempt.material ? LineRpcPath.EMAIL_VERIFY :
        LineRpcPath.EMAIL_VERIFY_PLAIN, new Uint8Array(), attempt, generation, result.verifier,
        LineRpcTimeout.EMAIL_VERIFY_MS);
      const verification = Codec.decodeVerification(bytes);
      let verifier: string;
      if (verification.kind === 'cancel') {
        throw new MiniAppError(LineErrorCode.EMAIL_VERIFICATION_REJECTED, 'LINE 主设备已取消登录');
      } else if (verification.kind === 'verifier' && !attempt.material && verification.verifier) {
        verifier = verification.verifier;
      } else if (verification.kind === 'e2ee' && attempt.material && verification.publicKey &&
        verification.encryptedKeyChain) {
        const proof = await this.crypto.confirmE2ee(attempt.material.privateKey,
          verification.publicKey, verification.encryptedKeyChain);
        try {
          this.assertCurrent(generation);
          const sequence: number = ++this.sequence;
          verifier = Codec.decodeConfirm(await this.call('confirmE2EELogin', LineRpcPath.AUTH,
            Codec.encodeConfirm(result.verifier, proof, sequence), attempt, generation), sequence);
        } finally {
          proof.fill(0);
        }
      } else {
        throw new MiniAppError(LineErrorCode.EMAIL_PROTOCOL_ERROR, 'LINE 主设备验证响应无效');
      }
      // APK 虽从邮箱入口发起，验证后的最终认证固定使用 LoginType.QRCODE。
      result = await this.authenticate(attempt, generation, systemName, modelName, LineEmailLoginType.QRCODE, verifier);
      if (!result.credential) {
        throw new MiniAppError(LineErrorCode.EMAIL_PROTOCOL_ERROR, 'LINE 未完成最终账号认证');
      }
      return result.credential;
    } finally {
      attempt.clear();
    }
  }

  private async authenticate(attempt: EmailAttempt, generation: number, systemName: string, modelName: string,
    type: LineEmailLoginType, verifier?: string): Promise<LineEmailLoginResult> {
    const rsaSequence: number = ++this.sequence;
    const key = Codec.decodeRsaKey(await this.call('getRSAKeyInfo', LineRpcPath.IDENTITY,
      Codec.encodeRsaKey(rsaSequence), attempt, generation), rsaSequence);
    const password: string = await this.crypto.createIdentity(key, attempt.email, attempt.password);
    this.assertCurrent(generation);
    const request: LineEmailLoginRequest = {
      type,
      keynm: key.keynm,
      password,
      systemName,
      modelName,
      verifier,
      e2eeVersion: attempt.material ? EMAIL_E2EE_VERSION : 0,
      secret: attempt.material?.secret
    };
    const sequence: number = ++this.sequence;
    return Codec.decodeLogin(await this.call('loginV2', LineRpcPath.AUTH,
      Codec.encodeLogin(request, sequence), attempt, generation), sequence);
  }

  private async call(method: string, path: string, body: Uint8Array, attempt: EmailAttempt, generation: number,
    sessionAccess?: string, timeoutMs: number = LineRpcTimeout.REQUEST_MS): Promise<Uint8Array> {
    this.assertCurrent(generation);
    const startedAt: number = Date.now();
    SdkLogger.info('LineEmailLogin', `${method}Started`);
    SdkLogger.debug('LineEmailLogin', `${method}Request`, { data: JSON.stringify(Array.from(body)) });
    let timer: number = -1;
    try {
      const deadline = new Promise<Uint8Array>((_resolve, reject): void => {
        timer = setTimeout((): void => reject(new MiniAppError(method === 'verifyEmailPin' ?
          LineErrorCode.EMAIL_VERIFICATION_TIMEOUT : LineErrorCode.RPC_TIMEOUT, 'LINE 认证请求超时')), timeoutMs);
      });
      const response = await Promise.race([this.transport.send({
        path,
        method,
        body,
        sessionAccess,
        timeoutMs
      }),
        attempt.cancelled, deadline]);
      this.assertCurrent(generation);
      SdkLogger.info('LineEmailLogin', `${method}Received`, { durationMs: Date.now() - startedAt });
      SdkLogger.debug('LineEmailLogin', `${method}Response`, { data: JSON.stringify(Array.from(response)) });
      return response;
    } finally {
      if (timer !== -1) {
        clearTimeout(timer);
      }
    }
  }

  private assertCurrent(generation: number): void {
    if (generation !== this.generation) {
      throw new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE 邮箱登录已取消');
    }
  }
}
