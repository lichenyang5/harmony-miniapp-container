import { url, util } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { SdkLogger } from '../../../logging/SdkLogger';
import { WebSchemeChain, WebSchemeDecision, WebSchemeHandler, WebSchemeRequest } from '../../../web/scheme/WebSchemeTypes';
import { LineAccountManager } from '../auth/LineAccountManager';
import { LineConsentRequest } from '../consent/LineConsentTypes';
import { LineConsentProtocol } from '../consent/LineConsentProtocol';
import { LineErrorCode } from '../LineErrorCode';
import { LineAdapter } from '../LineAdapter';
import { MiniAppLifecycle } from '../../../core/lifecycle/MiniAppLifecycle';
import { LineWebLoginClient } from '../weblogin/LineWebLoginClient';
import { LineWebLoginInput, LineWebLoginOptions } from '../weblogin/LineWebLoginTypes';
import { setLineWebLoginParameters, validateLineWebLoginReturn } from '../weblogin/LineWebLoginUrl';
import { LINE_ACCESS_HOST, LINE_OAUTH_LOGIN_PATHS } from './LineSchemeConstants';

const TAG: string = 'LineWebLogin';
/** Java Long.hashCode 使用毫秒的高、低 32 位异或。 */
const UINT32_BASE: number = 0x100000000;

function createSessionString(): string {
  const now: number = Date.now();
  return util.generateRandomUUID() + ((Math.floor(now / UINT32_BASE) | 0) ^ (now | 0)).toString(16);
}

/** 固定一次事务的账号和文档，不能把旧请求交给后来切换的账号。 */
class LineWebLoginOperation {
  readonly account: LineAccountManager;
  readonly accountVersion: number;
  readonly documentId: number;
  readonly input: LineWebLoginInput;
  readonly client: LineWebLoginClient;
  readonly visited: Set<string> = new Set<string>();
  consent?: LineConsentRequest;

  constructor(options: LineWebLoginOptions, account: LineAccountManager, address: string, liffId?: string) {
    this.account = account;
    this.accountVersion = account.getVersion();
    this.documentId = options.window.getDocumentId();
    this.input = { hookedFullUrl: address };
    this.client = new LineWebLoginClient(options.source, account, liffId);
  }
}

interface LineWebLoginContinuation {
  operation: LineWebLoginOperation;
  url: string;
}

/** 每个 WebView 独占；只由原生登录模式装配，不注入网页 JS。 */
export class LineWebLoginSchemeHandler implements WebSchemeHandler<WebSchemeRequest> {
  readonly id: string = 'line.webLogin';
  private readonly options: LineWebLoginOptions;
  private readonly adapter: LineAdapter;
  private readonly lifecycle: MiniAppLifecycle;
  private operation?: LineWebLoginOperation;
  private continuation?: LineWebLoginContinuation;
  private disposed: boolean = false;

  constructor(options: LineWebLoginOptions) {
    this.options = options;
    this.adapter = options.source === 'liff' ? options.session.getAdapter<LineAdapter>() : options.adapter;
    this.lifecycle = options.source === 'liff' ? options.session.lifecycle : options.lifecycle;
  }

  supports(request: WebSchemeRequest): boolean {
    if (!request.isMainFrame) {
      return false;
    }
    try {
      const parsed = new url.URL(request.url);
      return parsed.protocol === 'https:' && parsed.hostname === LINE_ACCESS_HOST &&
        !parsed.username && !parsed.password && (!parsed.port || parsed.port === '443') &&
        LINE_OAUTH_LOGIN_PATHS.some((path: string): boolean => parsed.pathname.startsWith(path));
    } catch (_) {
      return false;
    }
  }

  handle(request: WebSchemeRequest, chain: WebSchemeChain): WebSchemeDecision {
    if (this.disposed || !this.supports(request) || !this.lifecycle.isForeground() ||
      !this.options.window.isCurrent(this.options.window.getDocumentId())) {
      return chain.proceed();
    }
    const continuation = this.continuation;
    if (continuation && this.isOwnerCurrent(continuation.operation) && continuation.url === request.url) {
      this.continuation = undefined;
      return chain.proceed();
    }
    if (this.operation) {
      if (this.operation.input.hookedFullUrl !== request.url) {
        this.report(new MiniAppError(LineErrorCode.CONSENT_BUSY, 'LINE web login is already in progress'));
      }
      return WebSchemeDecision.CONSUME;
    }
    this.continuation = undefined;
    const account = this.adapter.getAccount();
    if (!account) {
      this.report(new MiniAppError(LineErrorCode.ACCOUNT_PROVIDER_REQUIRED, 'LINE account is unavailable'));
      return WebSchemeDecision.CONSUME;
    }
    const session = this.options.source === 'liff' ? this.options.session : undefined;
    const liffId: string | undefined = session ? this.adapter.getLiffId(session) : undefined;
    if (this.options.source === 'liff' && !liffId) {
      this.report(new MiniAppError(LineErrorCode.WEB_LOGIN_FAILED, 'LINE app state is unavailable'));
      return WebSchemeDecision.CONSUME;
    }
    const operation = new LineWebLoginOperation(this.options, account, request.url, liffId);
    this.operation = operation;
    this.run(operation);
    return WebSchemeDecision.CONSUME;
  }

  reset(): void {
    const operation = this.operation;
    // 先撤销所有权，关闭审批触发的 rejection 不能交付到新文档。
    this.operation = undefined;
    this.continuation = undefined;
    operation?.consent?.cancel();
  }

  dispose(): void {
    if (!this.disposed) {
      this.disposed = true;
      this.reset();
    }
  }

  private async run(operation: LineWebLoginOperation): Promise<void> {
    const invalidated = (): void => {
      if (this.operation === operation) {
        this.reset();
      }
    };
    let allowed: boolean = true;
    operation.account.addInvalidationListener(invalidated);
    SdkLogger.info(TAG, 'started', { code: this.options.source, documentId: operation.documentId });
    try {
      while (true) {
        this.assertCurrent(operation);
        const result = await operation.client.request(operation.input, allowed);
        this.assertCurrent(operation);
        if (result.returnUrl) {
          const navigation = this.options.window.prepare(validateLineWebLoginReturn(result.returnUrl), allowed,
            operation.documentId);
          // 许可匹配最终完整地址（含 MST），寿命独立于已经完成的 RPC 事务。
          this.continuation = { operation, url: navigation.url };
          await navigation.load();
          return;
        }
        if (!allowed || !result.consentUrl) {
          throw new MiniAppError(LineErrorCode.WEB_LOGIN_PROTOCOL_INVALID, 'Invalid LINE web login result');
        }
        const consentUrl: string = LineConsentProtocol.validateUrl(result.consentUrl);
        const sessionString: string = this.options.source === 'browser' ?
          operation.input.sessionString ?? createSessionString() :
          result.sessionString || operation.input.sessionString || createSessionString();
        operation.input.sessionString = sessionString;
        const progress: string = JSON.stringify([consentUrl, operation.input.sessionString]);
        if (operation.visited.has(progress)) {
          throw new MiniAppError(LineErrorCode.WEB_LOGIN_NO_PROGRESS, 'LINE web login consent did not progress');
        }
        operation.visited.add(progress);
        const parameters: Record<string, string> = {};
        parameters.sessionString = sessionString;
        const consent = this.options.consent.request({
          url: setLineWebLoginParameters(consentUrl, parameters), headers: operation.account.getWebAuthHeaders()
        });
        operation.consent = consent;
        try {
          allowed = await consent.result;
        } finally {
          if (operation.consent === consent) {
            operation.consent = undefined;
          }
        }
      }
    } catch (error) {
      if (this.continuation?.operation === operation) {
        this.continuation = undefined;
      }
      const failure = MiniAppError.from(error as Object, LineErrorCode.WEB_LOGIN_FAILED, 'LINE web login failed');
      if (this.operation === operation && this.isOwnerCurrent(operation) && failure.code !== LineErrorCode.CONSENT_CANCELLED) {
        this.report(failure);
      }
    } finally {
      operation.account.removeInvalidationListener(invalidated);
      if (this.operation === operation) {
        this.operation = undefined;
      }
    }
  }

  private isOwnerCurrent(operation: LineWebLoginOperation): boolean {
    return !this.disposed && this.lifecycle.isForeground() &&
      this.options.window.isCurrent(operation.documentId) &&
      this.adapter.getAccount() === operation.account && operation.account.getVersion() === operation.accountVersion;
  }

  private assertCurrent(operation: LineWebLoginOperation): void {
    if (this.operation !== operation || !this.isOwnerCurrent(operation)) {
      throw new MiniAppError(LineErrorCode.CONSENT_CANCELLED, 'LINE web login cancelled');
    }
  }

  private report(error: MiniAppError): void {
    try {
      this.options.onFailure(error);
    } catch (_) {
      SdkLogger.warn(TAG, 'failureCallbackFailed', { code: error.code });
    }
  }
}
