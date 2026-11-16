import { LineErrorCode } from '../LineErrorCode';
import { MiniAppError } from '../../../core/MiniAppError';
import { SdkLogger } from '../../../logging/SdkLogger';
import {
  LineAccountCredential,
  LineAccountOptions,
  LineQrLoginRunner,
  LineQrLoginState,
  LineRefreshTokenResult
} from './LineAccountTypes';
import { LineQrLoginClient } from './LineQrLoginClient';
import { LineHttpConnection, LineTransport, LineTransportRequest, LineClientRole, LineAccessKind } from '../network/LineTransport';
import { LineTokenRefreshClient } from './LineTokenRefreshClient';
import { LineHttpTransport } from '../network/LineHttpTransport';
import { LineNativeQrKeySource } from './LineQrKeySource';
import { LineConnInfoConnection, LineConnInfoProfile } from '../network/LineConnInfoConnection';
import { LineLiffAccount, LineLiffClient } from '../liff/LineLiffClient';
import { LineAccountStore } from './LineAccountStore';
import { LineEmailLoginRunner, LineEmailLoginState } from './LineEmailLoginTypes';
import { LineEmailLoginClient } from './LineEmailLoginClient';
import { LineNativeEmailLoginCrypto } from './LineEmailLoginCrypto';
import { LineAccountHeader } from '../network/LineRpcConstants';
import { LinePhoneRegistrationSession } from '../registration/LinePhoneRegistrationSession';
import { LineRegistrationClient, LineRegistrationTalkClient } from '../registration/LineRegistrationClient';
import { LineRegistrationDiagnostics } from '../registration/LineRegistrationDiagnostics';
import { LineRegistrationDevice, LineRegistrationDeviceInfo } from '../registration/LineRegistrationDevice';
import { LineNativeRegistrationPasswordCrypto } from '../registration/LineRegistrationCrypto';
import { LineRegistrationCreateResponse } from '../registration/LineRegistrationTypes';
import { LineRegistrationDependencies, LineRegistrationCheckpoint, LinePhoneRegistrationState,
  LineRegistrationSessionHooks, LineRegistrationAgreementContext, LineRegistrationTalkOperations } from '../registration/LineRegistrationSessionTypes';
import { LineAccountUiLease, LineAccountUiOwner } from './LineAccountUiLease';
import { LineRegistrationPresentationHost } from '../registration/ui/LineRegistrationPresentationHost';
import { common } from '@kit.AbilityKit';

// setTimeout 使用有符号 32 位毫秒值；超过上限时分段等待，不能让远期凭据立即失效。
const MAX_TIMER_DELAY_MS: number = 2147483647;

interface TokenRefreshTask {
  accessToken: string;
  result: Promise<void>;
}

/** A session-scoped sender; the closure keeps pending identity access inside the manager. */
class LineFinalizationTransport implements LineTransport {
  private readonly sender: (request: LineTransportRequest) => Promise<Uint8Array>;

  constructor(sender: (request: LineTransportRequest) => Promise<Uint8Array>) { this.sender = sender; }
  send(request: LineTransportRequest): Promise<Uint8Array> { return this.sender(request); }
}

/** 应用级的进程内账号状态；不绑定任意一个 WebView 或 LIFF ID。 */
export class LineAccountManager implements LineLiffAccount {
  private readonly runner: LineQrLoginRunner;
  private readonly emailRunner?: LineEmailLoginRunner;
  private loginKind?: 'qr' | 'email';
  private readonly systemName: string;
  private readonly modelName: string;
  private readonly transport?: LineTransport;
  // 登录、退出或失效都推进代次；认证、刷新和发行的迟到结果不得更新新账号。
  private generation: number = 0;
  private credential?: LineAccountCredential;
  // 当前沿用刷新期限作为保守使用截止时间，不代表服务端 accessToken 的真实过期时间。
  private expiresAt: number = 0;
  private expiryTimer: number = -1;
  private loginPending: boolean = false;
  private readonly refreshClient?: LineTokenRefreshClient;
  private refreshPending?: TokenRefreshTask;
  private restorePending?: Promise<boolean>;
  private readonly invalidationListeners: Set<() => void> = new Set<() => void>();
  private readonly store?: LineAccountStore;
  // 明确拒绝或主动退出后禁止回读旧存储；删除失败也不能在本进程再次复用它。
  private restoreBlocked: boolean = false;
  private readonly registrationDependencies: LineRegistrationDependencies;
  private readonly registrationContext?: common.Context;
  private registrationPending: boolean = false;
  private registrationSession?: LinePhoneRegistrationSession;

  constructor(runner: LineQrLoginRunner, systemName: string, modelName: string,
    transport?: LineTransport, options?: LineAccountOptions, emailRunner?: LineEmailLoginRunner,
    registrationDependencies: LineRegistrationDependencies = {}) {
    this.runner = runner;
    this.systemName = systemName;
    this.modelName = modelName;
    this.transport = transport;
    this.registrationDependencies = registrationDependencies;
    this.registrationContext = options?.storageContext;
    this.emailRunner = emailRunner ?? (transport ?
      new LineEmailLoginClient(transport, new LineNativeEmailLoginCrypto()) : undefined);
    if (transport) {
      this.refreshClient = new LineTokenRefreshClient(transport);
    }
    if (options?.persistent === true) {
      this.store = new LineAccountStore(options.storageContext);
    }
  }

  static withConnection(connection: LineHttpConnection, systemName: string, modelName: string,
    options?: LineAccountOptions): LineAccountManager {
    const transport: LineHttpTransport = new LineHttpTransport(connection);
    return new LineAccountManager(new LineQrLoginClient(transport, new LineNativeQrKeySource()),
      systemName, modelName, transport, options, undefined,
      { accountEndpoint: (): Promise<string> => connection.endpointFor('accountTalk') });
  }

  static withConnInfo(profile: LineConnInfoProfile, systemName: string, modelName: string,
    options?: LineAccountOptions): LineAccountManager {
    return LineAccountManager.withConnection(new LineConnInfoConnection(profile), systemName, modelName, options);
  }

  /** Low-level registration owns the same account slot as QR/email until it settles. */
  startPhoneRegistration(onState: (state: LinePhoneRegistrationState) => void): LinePhoneRegistrationSession {
    return this.startOwnedPhoneRegistration(onState);
  }

  /** Internal coordinator entry. An unrelated low-level caller cannot take a visible form. */
  startOwnedPhoneRegistration(onState: (state: LinePhoneRegistrationState) => void,
    owner?: LineAccountUiOwner): LinePhoneRegistrationSession {
    LineAccountUiLease.assertRegistrationOwner(this, owner);
    if (this.registrationPending || this.loginPending || this.restorePending) {
      throw new MiniAppError(LineErrorCode.LOGIN_IN_PROGRESS, 'LINE account operation is in progress');
    }
    if (this.credential && this.credential.stage !== 'pendingFinalization') {
      throw new MiniAppError(LineErrorCode.REGISTRATION_ACCOUNT_CONFLICT, 'Log out before registering another LINE account');
    }
    const transport = this.transport;
    if (!transport) { throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE transport is unavailable'); }
    this.registrationPending = true;
    const generation: number = ++this.generation;
    const dependencies = this.registrationDependencies;
    const diagnostics = new LineRegistrationDiagnostics();
    const hooks: LineRegistrationSessionHooks = {
      prepare: async (): Promise<LineRegistrationCheckpoint | undefined> => {
        this.assertCurrent(generation);
        if (!this.credential && !this.restoreBlocked) {
          const saved = this.store?.load();
          if (saved) {
            if (saved.credential.stage !== 'pendingFinalization') {
              throw new MiniAppError(LineErrorCode.REGISTRATION_ACCOUNT_CONFLICT, 'Log out before registering another LINE account');
            }
            this.credential = saved.credential; this.expiresAt = saved.expiresAt;
          }
        }
        this.applicationHeader(LineClientRole.PRIMARY);
        return this.credential?.registration;
      },
      device: (): LineRegistrationDeviceInfo => {
        if (dependencies.device) { return dependencies.device; }
        if (!this.registrationContext) {
          throw new MiniAppError(LineErrorCode.REGISTRATION_DEVICE_FAILED, 'LINE registration requires an application context');
        }
        return LineRegistrationDevice.get(this.registrationContext);
      },
      acceptCreated: async (response: LineRegistrationCreateResponse, checkpoint: LineRegistrationCheckpoint): Promise<void> => {
        this.assertCurrent(generation);
        const token = response.tokenV3IssueResult;
        // V1 cannot provide the refreshable primary identity required by this SDK.
        if (!response.mid || !token?.accessToken || !token.refreshToken ||
          !Number.isFinite(token.durationUntilRefreshInSec) || (token.durationUntilRefreshInSec ?? 0) <= 0) {
          throw new MiniAppError(LineErrorCode.REGISTRATION_CREATION_UNCERTAIN, 'Incomplete LINE account creation result');
        }
        const duration: number = token.durationUntilRefreshInSec ?? 0;
        const expiresAt: number = Date.now() + duration * 1000;
        if (!Number.isSafeInteger(expiresAt)) {
          throw new MiniAppError(LineErrorCode.REGISTRATION_CREATION_UNCERTAIN, 'Invalid LINE account creation lifetime');
        }
        this.credential = { mid: response.mid, accessToken: token.accessToken, refreshToken: token.refreshToken,
          certificate: '', loginSessionId: token.loginSessionId ?? '', durationUntilRefreshInSec: duration,
          metaData: new Map<string, string>(), role: LineClientRole.PRIMARY, stage: 'pendingFinalization', registration: checkpoint };
        this.expiresAt = expiresAt; this.restoreBlocked = false; this.clearExpiryTimer();
        this.store?.save(this.credential, expiresAt);
      },
      talk: (): LineRegistrationTalkOperations => {
        this.assertCurrent(generation);
        const credential = this.requirePending();
        const scoped: LineTransport = new LineFinalizationTransport((request: LineTransportRequest): Promise<Uint8Array> =>
          this.sendFinalizationRpc(request, generation));
        return dependencies.talkFactory ? dependencies.talkFactory(scoped, credential.accessToken) :
          new LineRegistrationTalkClient(scoped, credential.accessToken, LineClientRole.PRIMARY, diagnostics);
      },
      save: (checkpoint: LineRegistrationCheckpoint): void => {
        this.assertCurrent(generation); const credential = this.requirePending();
        credential.registration = checkpoint; this.store?.save(credential, this.expiresAt);
      },
      complete: (): void => {
        this.assertCurrent(generation); const credential = this.requirePending();
        credential.stage = 'ready'; credential.registration = undefined;
        this.store?.save(credential, this.expiresAt); this.scheduleExpiry();
      },
      release: (): void => {
        if (generation === this.generation) { this.registrationPending = false; this.registrationSession = undefined; }
      },
      assertIdentity: (): void => this.assertCurrent(generation),
      assertProfile: (mid: string): void => {
        this.assertCurrent(generation);
        if (this.requirePending().mid !== mid) { throw new MiniAppError(LineErrorCode.REGISTRATION_PROTOCOL_ERROR, 'LINE profile identity mismatch'); }
      },
      refreshPending: async (): Promise<void> => {
        this.assertCurrent(generation); await this.refreshCredential(this.requirePending(), generation);
      },
      agreementContext: (): Promise<LineRegistrationAgreementContext> => this.pendingAgreementContext(generation)
    };
    try {
      const session = new LinePhoneRegistrationSession(dependencies.client ?? new LineRegistrationClient(transport, diagnostics),
        dependencies.crypto ?? new LineNativeRegistrationPasswordCrypto(), hooks, onState,
        dependencies.presentationFactory?.() ?? new LineRegistrationPresentationHost(), dependencies.monotonicNow, diagnostics);
      this.registrationSession = session;
      return session;
    } catch (error) {
      this.registrationPending = false;
      throw new MiniAppError(LineErrorCode.REGISTRATION_FAILED, 'LINE registration could not start');
    }
  }

  private async sendFinalizationRpc(request: LineTransportRequest, generation: number): Promise<Uint8Array> {
    this.assertCurrent(generation);
    const credential = this.requirePending();
    if (Date.now() >= this.expiresAt) { await this.refreshCredential(credential, generation); }
    this.assertCurrent(generation);
    const transport = this.transport;
    if (!transport) { throw this.incomplete(); }
    const send = (): Promise<Uint8Array> => transport.send({ path: request.path, method: request.method,
      body: request.body, timeoutMs: request.timeoutMs, role: LineClientRole.PRIMARY,
      accessKind: LineAccessKind.ACCOUNT, sessionAccess: this.requirePending().accessToken });
    // Talk errors are decoded by the finalizer; its private hook performs a single refresh retry.
    const bytes = await send(); this.assertCurrent(generation);
    return bytes;
  }

  private async pendingAgreementContext(generation: number): Promise<LineRegistrationAgreementContext> {
    this.assertCurrent(generation);
    const credential = this.requirePending();
    const endpoint = this.registrationDependencies.accountEndpoint;
    if (!endpoint) { throw new MiniAppError(LineErrorCode.REGISTRATION_UNSUPPORTED, 'LINE policy endpoint is unavailable'); }
    if (Date.now() >= this.expiresAt) { await this.refreshCredential(credential, generation); }
    const url = await endpoint(); this.assertCurrent(generation);
    const application = this.applicationHeader(LineClientRole.PRIMARY);
    if (!application) { throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE primary identity is unavailable'); }
    const headers: Record<string, string> = {};
    headers[LineAccountHeader.ACCESS] = this.requirePending().accessToken;
    headers[LineAccountHeader.APPLICATION] = application;
    return { endpoint: url, headers };
  }

  private applicationHeader(role?: LineClientRole): string | undefined {
    if (role === LineClientRole.PRIMARY) {
      if (!this.transport?.applicationHeaderFor) {
        throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE primary identity is unavailable');
      }
      const application = this.transport.applicationHeaderFor(role);
      if (!application) { throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE primary identity is unavailable'); }
      return application;
    }
    return this.transport?.applicationHeaderFor?.(LineClientRole.SECONDARY) ?? this.transport?.applicationHeader;
  }

  private requirePending(): LineAccountCredential {
    if (!this.credential || this.credential.stage !== 'pendingFinalization' || this.credential.role !== LineClientRole.PRIMARY) {
      throw this.incomplete();
    }
    return this.credential;
  }

  private assertReady(): void { if (this.credential?.stage === 'pendingFinalization') { throw this.incomplete(); } }
  private incomplete(): MiniAppError {
    return new MiniAppError(LineErrorCode.REGISTRATION_INCOMPLETE, 'LINE account registration requires finalization');
  }

  /** 只恢复已配置的存储；恢复不启用持久化，也不隐式重试保存。 */
  async restoreSession(): Promise<boolean> {
    if (this.loginPending || this.registrationPending) {
      throw new MiniAppError(LineErrorCode.LOGIN_IN_PROGRESS, 'LINE 登录正在进行');
    }
    this.assertReady();
    if (this.restoreBlocked) {
      return false;
    }
    if (!this.store) {
      return this.getAccountId() !== undefined;
    }
    if (this.credential && Date.now() < this.expiresAt) {
      return true;
    }
    if (this.credential) {
      // 先关闭旧凭据所属窗口，再开始恢复；后续同步读取不能打断刷新。
      this.invalidateExpired();
      if (this.loginPending) {
        throw new MiniAppError(LineErrorCode.LOGIN_IN_PROGRESS, 'LINE 登录正在进行');
      }
      if (this.restoreBlocked) {
        return false;
      }
    }
    if (this.restorePending) {
      return this.restorePending;
    }
    const pending: Promise<boolean> = this.restoreStoredSession();
    this.restorePending = pending;
    try {
      return await pending;
    } finally {
      if (this.restorePending === pending) {
        this.restorePending = undefined;
      }
    }
  }

  async startQrLogin(onState: (state: LineQrLoginState) => void,
    onStarted?: (version: number) => void): Promise<string> {
    const generation: number = this.beginLogin('qr');
    try {
      onStarted?.(generation);
      this.assertCurrent(generation);
    } catch (error) {
      this.cancelLogin(generation);
      throw MiniAppError.from(error as Object, LineErrorCode.LOGIN_FAILED, 'LINE 扫码登录启动失败');
    }
    let result: LineAccountCredential;
    try {
      result = await this.runner.login(this.systemName, this.modelName,
        (state: LineQrLoginState): void => {
          if (generation === this.generation && state.kind !== 'authorized') {
            try {
              onState(state);
            } catch (_) { /* 宿主 UI 异常不改变登录协议状态。 */
            }
          }
        });
    } catch (error) {
      this.finishFailedLogin(generation);
      throw MiniAppError.from(error as Object, LineErrorCode.LOGIN_FAILED, 'LINE 扫码登录失败');
    }
    this.completeLogin(result, generation);
    try {
      onState({ kind: 'authorized', mid: result.mid });
    } catch (_) { /* 凭据已发布。 */
    }
    return result.mid;
  }

  /** 邮箱和密码只交给本次认证流程；管理器不保存明文或把它们交付给网页。 */
  async startEmailLogin(email: string, password: string,
    onState: (state: LineEmailLoginState) => void,
    onStarted?: (version: number) => void): Promise<string> {
    if (typeof email !== 'string' || !email || typeof password !== 'string' || !password) {
      throw new MiniAppError(LineErrorCode.EMAIL_INVALID_ARGUMENT, '请输入 LINE 邮箱和密码');
    }
    if (!this.emailRunner) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 邮箱认证传输未配置');
    }
    const generation: number = this.beginLogin('email');
    try {
      onStarted?.(generation);
      this.assertCurrent(generation);
    } catch (error) {
      this.cancelLogin(generation);
      throw MiniAppError.from(error as Object, LineErrorCode.EMAIL_LOGIN_FAILED, 'LINE 邮箱登录启动失败');
    }
    let result: LineAccountCredential;
    try {
      const pending = this.emailRunner.login(email, password, this.systemName, this.modelName,
        (state: LineEmailLoginState): void => {
          if (generation === this.generation && state.kind !== 'authorized') {
            try {
              onState(state);
            } catch (_) { /* UI 失败不改变认证。 */
            }
          }
        });
      email = '';
      password = '';
      result = await pending;
    } catch (error) {
      this.finishFailedLogin(generation);
      throw MiniAppError.from(error as Object, LineErrorCode.EMAIL_LOGIN_FAILED, 'LINE 邮箱认证失败');
    }
    this.completeLogin(result, generation);
    try {
      onState({ kind: 'authorized', mid: result.mid });
    } catch (_) { /* 凭据已发布。 */
    }
    return result.mid;
  }

  cancelQrLogin(expectedVersion?: number): void {
    if (this.loginKind === 'qr') {
      this.cancelLogin(expectedVersion);
    }
  }

  /** 取消当前任意认证方式；不等同于退出已经完成的账号会话。 */
  cancelLogin(expectedVersion?: number): void {
    if (!this.loginPending || (expectedVersion !== undefined && expectedVersion !== this.generation)) {
      return;
    }
    this.loginPending = false;
    this.generation++;
    const kind = this.loginKind;
    this.loginKind = undefined;
    if (kind === 'email') {
      this.emailRunner?.cancel();
    } else {
      this.runner.cancel();
    }
  }

  logout(): void {
    this.restoreBlocked = true;
    this.restorePending = undefined;
    this.registrationSession?.cancel();
    this.registrationSession = undefined;
    this.registrationPending = false;
    this.cancelLogin();
    this.generation++;
    this.refreshPending = undefined;
    this.runner.cancel();
    this.credential = undefined;
    this.expiresAt = 0;
    this.clearExpiryTimer();
    this.notifyInvalidated();
    this.store?.clear();
  }

  addInvalidationListener(listener: () => void): void {
    this.invalidationListeners.add(listener);
  }

  removeInvalidationListener(listener: () => void): void {
    this.invalidationListeners.delete(listener);
  }

  getAccountId(): string | undefined {
    if (this.credential?.stage === 'pendingFinalization') { return undefined; }
    if (this.credential && Date.now() >= this.expiresAt) {
      this.invalidateExpired();
    }
    if (!this.credential) {
      return undefined;
    }
    return this.credential.mid;
  }

  getVersion(): number {
    return this.generation;
  }

  /** 仅供原生官方授权页首请求使用；不注入普通小程序或网页脚本。 */
  getWebAuthHeaders(): Record<string, string> {
    const access: string = this.requireAccessToken();
    const application: string | undefined = this.applicationHeader(this.credential?.role);
    if (!application) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 客户端标识不可用');
    }
    const headers: Record<string, string> = {};
    headers[LineAccountHeader.ACCESS] = access;
    headers[LineAccountHeader.APPLICATION] = application;
    return headers;
  }

  /** 只供 LINE 内部 RPC 传输调用；绝不交付网页桥或登录 UI。 */
  requireAccessToken(): string {
    this.assertReady();
    if (this.credential && Date.now() >= this.expiresAt) {
      this.invalidateExpired();
    }
    if (!this.credential) {
      throw new MiniAppError(LineErrorCode.LOGIN_REQUIRED, 'LINE 账号未登录或凭据已过期');
    }
    return this.credential.accessToken;
  }

  /** 内部鉴权入口：合并并发刷新，且不得跨账号代次发布凭据。 */
  async refreshRejectedToken(previousToken: string, generation: number): Promise<void> {
    this.assertReady();
    this.assertCurrent(generation);
    if (!this.credential || !this.refreshClient) {
      throw new MiniAppError(LineErrorCode.LOGIN_REQUIRED, 'LINE 账号凭据不可用');
    }
    if (this.credential.accessToken !== previousToken) {
      return;
    }
    const currentTask: TokenRefreshTask | undefined = this.refreshPending;
    if (currentTask && currentTask.accessToken !== previousToken) {
      // 新 Token 的拒绝不能合并为旧 Token 的刷新成功；等旧任务收尾后重新检查账号和凭据。
      try {
        await currentTask.result;
      } finally {
        if (this.refreshPending === currentTask) {
          this.refreshPending = undefined;
        }
      }
      this.assertCurrent(generation);
      return this.refreshRejectedToken(previousToken, generation);
    }
    if (!this.refreshPending) {
      const credential: LineAccountCredential = this.credential;
      this.refreshPending = {
        accessToken: previousToken,
        result: (async (): Promise<void> => {
          SdkLogger.info('LineAccount', 'tokenRefreshStarted');
          await this.refreshCredential(credential, generation);
          this.assertCurrent(generation);
          SdkLogger.info('LineAccount', 'tokenRefreshCompleted');
        })()
      };
    }
    const pending: TokenRefreshTask = this.refreshPending;
    try {
      await pending.result;
    } catch (error) {
      const failure: MiniAppError = MiniAppError.from(error as Object,
        LineErrorCode.TOKEN_REFRESH_FAILED, 'LINE 账号刷新失败');
      SdkLogger.warn('LineAccount', 'tokenRefreshFailed', { code: failure.code });
      if (LineErrorCode.isTokenRefreshRejected(failure.code)) {
        this.invalidateRejectedCredential(previousToken, generation, failure.code);
      }
      throw failure;
    } finally {
      if (this.refreshPending === pending) {
        this.refreshPending = undefined;
      }
    }
  }

  /** 重试本地保存，不发起扫码或刷新；上次登录已成功时由宿主显式调用。 */
  saveSession(): boolean {
    if (!this.store) {
      throw new MiniAppError(LineErrorCode.ACCOUNT_STORAGE_DISABLED, 'LINE 持久化未启用');
    }
    this.requireAccessToken();
    if (this.credential) {
      return this.store.save(this.credential, this.expiresAt);
    }
    return false;
  }

  /** 原生内部鉴权传输：覆盖账号头并检查请求前后的账号代次。 */
  async sendAccountRpc(request: LineTransportRequest): Promise<Uint8Array> {
    if (!this.transport) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 传输未配置');
    }
    const generation: number = this.generation;
    const bytes = await this.transport.send({
      path: request.path,
      method: request.method,
      body: request.body,
      liffId: request.liffId,
      timeoutMs: request.timeoutMs,
      sessionAccess: this.requireAccessToken(),
      role: this.credential?.role,
      accessKind: this.credential?.role === undefined ? undefined : LineAccessKind.ACCOUNT
    });
    this.assertCurrent(generation);
    this.requireAccessToken();
    return bytes;
  }

  /** 保留现有调用入口；LIFF 业务解码和重试归发行客户端，不在账号管理器实现。 */
  async sendLiffRpc(method: string, body: Uint8Array, liffId: string, sequence?: number): Promise<Uint8Array> {
    return new LineLiffClient(this).send(method, body, liffId, sequence);
  }

  private async restoreStoredSession(): Promise<boolean> {
    const store: LineAccountStore | undefined = this.store;
    if (!store) {
      return false;
    }
    const saved = store.load();
    if (!saved) {
      return false;
    }
    const generation: number = this.generation;
    let expiresAt: number = saved.expiresAt;
    if (saved.credential.stage === 'pendingFinalization') {
      this.assertCurrent(generation);
      this.credential = saved.credential; this.expiresAt = expiresAt;
      throw this.incomplete();
    }
    if (Date.now() >= expiresAt) {
      try {
        expiresAt = await this.refreshCredential(saved.credential, generation);
      } catch (error) {
        const failure: MiniAppError = MiniAppError.from(error as Object,
          LineErrorCode.ACCOUNT_RESTORE_FAILED, 'LINE 账号恢复失败');
        if (LineErrorCode.isTokenRefreshRejected(failure.code) && this.generation === generation &&
          !this.restoreBlocked && !this.loginPending) {
          this.restoreBlocked = true;
          this.generation++;
          this.store?.clear();
          this.notifyInvalidated();
          return false;
        }
        this.assertCurrent(generation);
        throw failure;
      }
    }
    this.assertCurrent(generation);
    this.credential = saved.credential;
    this.expiresAt = expiresAt;
    this.scheduleExpiry();
    return true;
  }

  /** 扫码、邮箱与存储恢复共用：上报当前 Token → 刷新 → 保存 → 上报新 Token。 */
  private async refreshCredential(credential: LineAccountCredential, generation: number): Promise<number> {
    const client: LineTokenRefreshClient | undefined = this.refreshClient;
    if (!client) {
      throw new MiniAppError(LineErrorCode.LOGIN_REQUIRED, 'LINE 账号凭据不可用');
    }
    this.assertCurrent(generation);
    SdkLogger.info('LineAccount', 'tokenPreReportStarted');
    try {
      await client.reportRefreshedAccessToken(credential.accessToken, credential.role);
    } catch (error) {
      this.assertCurrent(generation);
      const failure: MiniAppError = MiniAppError.from(error as Object,
        LineErrorCode.TOKEN_REFRESH_FAILED, 'LINE 账号刷新前上报失败');
      SdkLogger.warn('LineAccount', 'tokenPreReportFailed', { code: failure.code });
      // APK 的前置报告对 INVALID_REQUEST 正常返回，继续 refresh；只有 refresh 的拒绝才使凭据失效。
      if (!LineErrorCode.isTokenRefreshRejected(failure.code)) {
        throw failure;
      }
    }
    this.assertCurrent(generation);
    SdkLogger.info('LineAccount', 'tokenPreReportCompleted');
    const role: LineClientRole | undefined = credential.role;
    const result: LineRefreshTokenResult = await client.refresh(credential.refreshToken, credential.accessToken, role);
    this.assertCurrent(generation);
    credential.accessToken = result.accessToken;
    if (result.refreshToken) {
      credential.refreshToken = result.refreshToken;
    }
    credential.durationUntilRefreshInSec = result.durationUntilRefreshInSec;
    const expiresAt: number = Date.now() + result.durationUntilRefreshInSec * 1000;
    if (this.credential === credential) {
      this.expiresAt = expiresAt;
      this.scheduleExpiry();
    }
    // 轮换已经成功，先保存新凭据；后置报告失败也不能恢复旧 refreshToken。
    this.store?.save(credential, expiresAt);
    // APK 保存后独立调度报告；不让报告的网络等待占用刷新任务或 LIFF 发行预算。
    this.reportRefreshedToken(client, credential.accessToken, generation, role);
    return expiresAt;
  }

  /** 后置报告只观察本次 Token；失败和迟到结果都不修改账号或存储。 */
  private async reportRefreshedToken(client: LineTokenRefreshClient, accessToken: string,
    generation: number, role?: LineClientRole): Promise<void> {
    try {
      if (generation !== this.generation) {
        return;
      }
      SdkLogger.info('LineAccount', 'tokenPostReportStarted');
      await client.reportRefreshedAccessToken(accessToken, role);
      if (generation !== this.generation || this.credential?.accessToken !== accessToken) {
        return;
      }
      SdkLogger.info('LineAccount', 'tokenPostReportCompleted');
    } catch (error) {
      if (generation !== this.generation || this.credential?.accessToken !== accessToken) {
        return;
      }
      // APK fa0/o.c 同样捕获报告失败；保留已发布的新凭据，不让上报失败触发账号失效。
      const failure: MiniAppError = MiniAppError.from(error as Object,
        LineErrorCode.TOKEN_REFRESH_FAILED, 'LINE 账号刷新后上报失败');
      SdkLogger.warn('LineAccount', 'tokenPostReportFailed', { code: failure.code });
    }
  }

  private beginLogin(kind: 'qr' | 'email'): number {
    if (this.registrationPending) {
      throw new MiniAppError(LineErrorCode.LOGIN_IN_PROGRESS, 'LINE registration is in progress');
    }
    this.assertReady();
    if (!this.restoreBlocked && this.store?.load()?.credential.stage === 'pendingFinalization') { throw this.incomplete(); }
    this.cancelLogin();
    this.restoreBlocked = true;
    this.restorePending = undefined;
    this.store?.clear();
    this.generation++;
    this.refreshPending = undefined;
    const hadCredential: boolean = this.credential !== undefined;
    this.credential = undefined;
    this.expiresAt = 0;
    this.clearExpiryTimer();
    const generation: number = this.generation;
    this.loginPending = true;
    this.loginKind = kind;
    if (hadCredential) {
      this.notifyInvalidated();
    }
    this.assertCurrent(generation);
    return generation;
  }

  private finishFailedLogin(generation: number): void {
    this.assertCurrent(generation);
    this.loginPending = false;
    this.loginKind = undefined;
  }

  private completeLogin(result: LineAccountCredential, generation: number): void {
    this.assertCurrent(generation);
    this.loginPending = false;
    this.loginKind = undefined;
    const expiresAt: number = Date.now() + result.durationUntilRefreshInSec * 1000;
    this.credential = result;
    this.restoreBlocked = false;
    this.expiresAt = expiresAt;
    this.scheduleExpiry();
    // 服务认证已经成功；本地保存只负责下次恢复，失败不改变本次登录或 authorized 事件。
    this.store?.save(result, expiresAt);
  }

  private assertCurrent(generation: number): void {
    if (generation !== this.generation) {
      throw new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE 登录已取消或账号已切换');
    }
  }

  private clearExpiryTimer(): void {
    if (this.expiryTimer !== -1) {
      clearTimeout(this.expiryTimer);
    }
    this.expiryTimer = -1;
  }

  private scheduleExpiry(): void {
    this.clearExpiryTimer();
    if (!this.credential || this.credential.stage === 'pendingFinalization') {
      return;
    }
    const delay: number = Math.max(1, Math.min(this.expiresAt - Date.now(), MAX_TIMER_DELAY_MS));
    this.expiryTimer = setTimeout((): void => {
      if (Date.now() >= this.expiresAt) {
        this.invalidateExpired();
      } else {
        this.scheduleExpiry();
      }
    }, delay);
  }

  private invalidateExpired(): void {
    if (!this.credential || this.credential.stage === 'pendingFinalization') {
      return;
    }
    this.generation++;
    this.credential = undefined;
    this.expiresAt = 0;
    this.clearExpiryTimer();
    this.notifyInvalidated();
  }

  /** 只清理由这次刷新使用的凭据；迟到的旧账号拒绝不得清除新登录及其存储。 */
  private invalidateRejectedCredential(previousToken: string, generation: number, code: string): void {
    if (generation !== this.generation || this.credential?.accessToken !== previousToken) {
      return;
    }
    this.restoreBlocked = true;
    this.generation++;
    this.credential = undefined;
    this.expiresAt = 0;
    this.refreshPending = undefined;
    this.clearExpiryTimer();
    // 先清存储再通知宿主，避免同步回调启动新登录后又被旧清理覆盖。
    this.store?.clear();
    SdkLogger.info('LineAccount', 'sessionInvalidated', { code });
    this.notifyInvalidated();
  }

  private notifyInvalidated(): void {
    this.invalidationListeners.forEach((listener: () => void): void => {
      try {
        listener();
      } catch (_) { /* 一个窗口失败不影响其他窗口退出。 */
      }
    });
  }
}
