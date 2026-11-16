import { LineRpcPath, LineRpcTimeout } from '../network/LineRpcConstants';
import { LineErrorCode } from '../LineErrorCode';
import { util } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { SdkLogger } from '../../../logging/SdkLogger';
import { LineQrLoginCodec } from './LineQrLoginCodec';
import {
  LINE_QR_KEY_BYTES,
  LineAccountCredential,
  LineQrCodeResponse,
  LineQrKeySource,
  LineQrLoginRequest,
  LineQrLoginRunner,
  LineQrLoginState
} from './LineAccountTypes';
import { LineTransport } from '../network/LineTransport';


interface LoginStage {
  method: string;
  failureCode: string;
}

interface LoginFailureDetails {
  code?: string | number;
  name?: string;
}

/** 只推进一次扫码登录；账号持有与 LIFF 发行由上层账号管理器承担。 */
export class LineQrLoginClient implements LineQrLoginRunner {
  private readonly transport: LineTransport;
  private readonly keys: LineQrKeySource;
  private sequence: number = 0;
  private generation: number = 0;
  private cancelQrWait?: () => void;

  constructor(transport: LineTransport, keys: LineQrKeySource) {
    this.transport = transport;
    this.keys = keys;
  }

  cancel(): void {
    this.generation++;
    this.cancelQrWait?.();
  }

  async login(systemName: string, modelName: string,
    onState: (state: LineQrLoginState) => void): Promise<LineAccountCredential> {
    const stage: LoginStage = { method: 'createSession', failureCode: LineErrorCode.LOGIN_FAILED_CREATE_SESSION };
    try {
      return await this.runLogin(systemName, modelName, onState, stage);
    } catch (error) {
      const failure: MiniAppError = MiniAppError.from(error as Object, stage.failureCode,
        'LINE 扫码登录阶段失败');
      if (failure.code !== LineErrorCode.LOGIN_CANCELLED) {
        SdkLogger.warn('LineQrLogin', `${stage.method}Failed`, {
          code: this.diagnosticCode(error as Object)
        });
      }
      throw failure;
    }
  }

  private assertCurrent(generation: number): void {
    if (generation !== this.generation) {
      throw new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE 扫码登录已取消');
    }
  }

  private diagnosticCode(error: Object): string {
    const detail = error as LoginFailureDetails;
    if (typeof detail.code === 'string' && /^LINE_[A-Z0-9_]{1,60}$/.test(detail.code)) {
      return detail.code;
    }
    if (typeof detail.code === 'number' && Number.isSafeInteger(detail.code)) {
      return LineErrorCode.nativeDiagnostic(detail.code);
    }
    if (detail.name === 'MiniAppError' || detail.name === 'BusinessError' ||
      detail.name === 'TypeError' || detail.name === 'RangeError' || detail.name === 'Error') {
      return detail.name;
    }
    return 'UNKNOWN_ERROR';
  }

  private async call(method: string, path: string, body: Uint8Array,
    generation: number, sessionAccess?: string, timeoutMs?: number): Promise<Uint8Array> {
    this.assertCurrent(generation);
    const startedAt: number = Date.now();
    SdkLogger.info('LineQrLogin', `${method}Started`, {});
    SdkLogger.debug('LineQrLogin', `${method}Request`, { data: JSON.stringify(Array.from(body)) });
    const response = await this.transport.send({
      path,
      method,
      body,
      sessionAccess,
      timeoutMs
    });
    this.assertCurrent(generation);
    SdkLogger.info('LineQrLogin', `${method}Received`, { durationMs: Date.now() - startedAt });
    SdkLogger.debug('LineQrLogin', `${method}Response`, { data: JSON.stringify(Array.from(response)) });
    return response;
  }

  private async runLogin(systemName: string, modelName: string,
    onState: (state: LineQrLoginState) => void, stage: LoginStage): Promise<LineAccountCredential> {
    if (!systemName || !modelName) {
      throw new MiniAppError(LineErrorCode.LOGIN_INVALID_DEVICE, 'LINE 登录缺少设备信息');
    }
    this.cancel();
    const generation = this.generation;
    const createSequence = ++this.sequence;
    const sessionId = LineQrLoginCodec.decodeCreateSession(await this.call(
      'createSession', LineRpcPath.LOGIN, LineQrLoginCodec.encodeCreateSession(createSequence), generation),
      createSequence);
    this.assertCurrent(generation);
    const keyPair = await this.keys.create();
    const validKeyPair: boolean = keyPair.publicKey.length === LINE_QR_KEY_BYTES &&
      keyPair.privateKey.length === LINE_QR_KEY_BYTES;
    keyPair.privateKey.fill(0);
    this.assertCurrent(generation);
    if (!validKeyPair) {
      throw new MiniAppError(LineErrorCode.LOGIN_KEY_INVALID, 'LINE 安全二维码密钥无效');
    }
    const qrSequence = ++this.sequence;
    stage.method = 'createQrCodeForSecure';
    stage.failureCode = LineErrorCode.LOGIN_FAILED_CREATE_QR_CODE;
    const qr: LineQrCodeResponse = LineQrLoginCodec.decodeCreateQrCode(await this.call(
      'createQrCodeForSecure', LineRpcPath.LOGIN,
      LineQrLoginCodec.encodeCreateQrCode(sessionId, qrSequence), generation), qrSequence);
    this.assertCurrent(generation);
    const secret = new util.Base64Helper().encodeToStringSync(keyPair.publicKey).replace(/[\r\n]/g, '');
    const intervalMs: number = qr.longPollingIntervalSec > 0 ?
      qr.longPollingIntervalSec * 1000 : LineRpcTimeout.POLL_MS;
    // 沿用服务端轮询次数与间隔形成等待预算，不额外猜测二维码服务端有效期。
    const expiresAt: number = Date.now() + intervalMs * qr.longPollingMaxCount;
    onState({ kind: 'qrReady', url: qr.callbackUrl + '?secret=' + encodeURIComponent(secret) + '&e2eeVersion=1' });
    this.assertCurrent(generation);
    await this.waitForQrVerification(qr, sessionId, generation, stage, intervalMs, expiresAt);
    this.assertCurrent(generation);
    onState({ kind: 'qrVerified' });
    this.assertCurrent(generation);

    const certificateSequence = ++this.sequence;
    stage.method = 'verifyCertificateEncode';
    stage.failureCode = LineErrorCode.LOGIN_FAILED_VERIFY_CERTIFICATE_ENCODE;
    const certificateRequest: Uint8Array = LineQrLoginCodec.encodeVerifyCertificate(
      sessionId, '', certificateSequence);
    stage.method = 'verifyCertificateSend';
    stage.failureCode = LineErrorCode.LOGIN_FAILED_VERIFY_CERTIFICATE_SEND;
    const certificateResponse: Uint8Array = await this.call(
      'verifyCertificate', LineRpcPath.LOGIN, certificateRequest, generation);
    stage.method = 'verifyCertificateDecode';
    stage.failureCode = LineErrorCode.LOGIN_FAILED_VERIFY_CERTIFICATE_DECODE;
    const hasValidCertificate: boolean = LineQrLoginCodec.decodeVerifyCertificate(
      certificateResponse, certificateSequence);
    this.assertCurrent(generation);
    if (!hasValidCertificate) {
      const pinSequence = ++this.sequence;
      stage.method = 'createPinCode';
      stage.failureCode = LineErrorCode.LOGIN_FAILED_CREATE_PIN_CODE;
      const pin: string = LineQrLoginCodec.decodeCreatePinCode(await this.call(
        'createPinCode', LineRpcPath.LOGIN, LineQrLoginCodec.encodeCreatePinCode(sessionId, pinSequence),
        generation), pinSequence);
      onState({ kind: 'pinReady', pin });
      this.assertCurrent(generation);
      const pinPollSequence = ++this.sequence;
      stage.method = 'checkPinCodeVerified';
      stage.failureCode = LineErrorCode.LOGIN_FAILED_CHECK_PIN_CODE;
      LineQrLoginCodec.decodeCheckPinCodeVerified(await this.call(
        'checkPinCodeVerified', LineRpcPath.POLL,
        LineQrLoginCodec.encodeCheckPinCodeVerified(sessionId, pinPollSequence), generation,
        sessionId, LineRpcTimeout.POLL_MS), pinPollSequence);
    }

    const request: LineQrLoginRequest = {
      authSessionId: sessionId,
      systemName,
      modelName,
      autoLoginIsRequired: true,
      nonce: qr.nonce
    };
    const loginSequence = ++this.sequence;
    stage.method = 'qrCodeLoginV2ForSecure';
    stage.failureCode = LineErrorCode.LOGIN_FAILED_QR_CODE_LOGIN;
    const result: LineAccountCredential = LineQrLoginCodec.decodeQrCodeLogin(await this.call(
      'qrCodeLoginV2ForSecure', LineRpcPath.LOGIN,
      LineQrLoginCodec.encodeQrCodeLogin(request, loginSequence), generation), loginSequence);
    this.assertCurrent(generation);
    onState({ kind: 'authorized', mid: result.mid });
    return result;
  }

  /** 截止时间独立于网络回包；到期/取消后，迟到轮询不得继续请求或进入 PIN 阶段。 */
  private async waitForQrVerification(qr: LineQrCodeResponse, sessionId: string, generation: number,
    stage: LoginStage, intervalMs: number, expiresAt: number): Promise<void> {
    let finished: boolean = false;
    let timer: number = -1;
    let cancelWait: () => void = (): void => {
    };
    const deadline = new Promise<void>((_resolve, reject): void => {
      timer = setTimeout((): void => {
        reject(new MiniAppError(LineErrorCode.QR_CONFIRM_TIMEOUT, 'LINE 扫码确认超时'));
      }, Math.max(0, expiresAt - Date.now()));
      cancelWait = (): void => {
        reject(new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE 扫码登录已取消'));
      };
    });
    this.cancelQrWait = cancelWait;
    const poll = async (): Promise<void> => {
      for (let attempt: number = 0; attempt < qr.longPollingMaxCount; attempt++) {
        this.assertCurrent(generation);
        if (finished || Date.now() >= expiresAt) {
          throw new MiniAppError(LineErrorCode.QR_CONFIRM_TIMEOUT, 'LINE 扫码确认超时');
        }
        const pollSequence = ++this.sequence;
        stage.method = 'checkQrCodeVerified';
        stage.failureCode = LineErrorCode.LOGIN_FAILED_CHECK_QR_CODE;
        try {
          const response: Uint8Array = await this.call('checkQrCodeVerified', LineRpcPath.POLL,
            LineQrLoginCodec.encodeCheckQrCodeVerified(sessionId, pollSequence), generation,
            sessionId, Math.min(intervalMs, expiresAt - Date.now()));
          if (finished || Date.now() >= expiresAt) {
            throw new MiniAppError(LineErrorCode.QR_CONFIRM_TIMEOUT, 'LINE 扫码确认超时');
          }
          LineQrLoginCodec.decodeCheckQrCodeVerified(response, pollSequence);
          return;
        } catch (error) {
          this.assertCurrent(generation);
          if (finished || !(error instanceof MiniAppError) || error.code !== LineErrorCode.QR_POLL_TIMEOUT) {
            throw MiniAppError.from(error as Object, LineErrorCode.QR_POLL_FAILED, 'LINE 扫码确认失败');
          }
        }
      }
      throw new MiniAppError(LineErrorCode.QR_CONFIRM_TIMEOUT, 'LINE 扫码确认超时');
    };
    try {
      await Promise.race([poll(), deadline]);
    } finally {
      finished = true;
      clearTimeout(timer);
      if (this.cancelQrWait === cancelWait) {
        this.cancelQrWait = undefined;
      }
    }
  }
}
