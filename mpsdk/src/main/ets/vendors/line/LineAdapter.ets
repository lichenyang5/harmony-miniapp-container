import { LineRegistrationRequest } from './registration/LineRegistrationUiTypes';
import { LineRegistrationDialogHost } from './registration/ui/LineRegistrationDialogHost';
import { MiniAppAdapter } from '../../core/MiniAppAdapter';
import { LINE_VENDOR_ID } from './LineConstants';
import { LineHost, LineLiffViewResult, LineSubViewRequest, LineSubWindowResultRequest } from './liff/LineLiffTypes';
import { LineSubViewService } from './liff/LineSubViewService';
import { LineNavigationController } from './LineNavigationController';
import { MiniAppError } from '../../core/MiniAppError';
import { LineAccountManager } from './auth/LineAccountManager';
import { common } from '@kit.AbilityKit';
import { LineMode } from './LineMode';
import { LineErrorCode } from './LineErrorCode';
import { INVALID_ARGUMENT } from '../../core/MiniAppErrorCode';
import { LineDefaultAccount } from './auth/LineDefaultAccount';
import { LineLoginCoordinator } from './auth/LineLoginCoordinator';
import { LineLoginRequest } from './auth/LineLoginTypes';
import { LineLoginDialogHost } from './auth/ui/LineLoginDialogHost';
import { MiniAppSession } from '../../core/Runtime';
import { LineBinding } from './LineVendor';

export class LineAdapter extends MiniAppAdapter<LineHost | undefined> {
  readonly vendorId: string = LINE_VENDOR_ID;
  readonly mode: LineMode;
  readonly webContextType: string;
  readonly forceLogin: boolean;
  private readonly subViews: LineSubViewService;

  constructor(host?: LineHost) {
    super(host);
    this.mode = host?.mode ?? LineMode.WEB;
    if (this.mode !== LineMode.CLIENT && this.mode !== LineMode.WEB && this.mode !== LineMode.WEB_HOOK) {
      throw new MiniAppError(INVALID_ARGUMENT, 'Invalid LINE mode');
    }
    if (host?.loginPolicy !== undefined && host.loginPolicy !== 'interactive' && host.loginPolicy !== 'reuseOnly') {
      throw new MiniAppError(INVALID_ARGUMENT, 'Invalid LINE login policy');
    }
    this.webContextType = host?.webContextType ?? 'none';
    this.forceLogin = host?.forceLogin ?? false;
    this.subViews = new LineSubViewService(host);
  }

  issueSubLiffView(request: LineSubViewRequest): Promise<LineLiffViewResult> {
    const account = this.getAccount();
    if (account) {
      return new LineSubViewService({ account }).issue(request);
    }
    return this.subViews.issue(request);
  }

  /** 子窗口销毁后的原生收尾；不需要持有已释放的 WebView。 */
  storeSubWindowResult(request: LineSubWindowResultRequest): Promise<void> {
    const account = this.getAccount();
    return account ? new LineSubViewService({ account }).storeResult(request) : this.subViews.storeResult(request);
  }

  getAccount(): LineAccountManager | undefined {
    return this.mode !== LineMode.CLIENT ? undefined : this.host?.account ?? LineDefaultAccount.peek();
  }

  /** 读取指定会话已建立的协议身份；Adapter 可共享，不缓存 ID，也不以入口别名兜底。 */
  getLiffId(session: MiniAppSession): string | undefined {
    if (session.vendorId !== LINE_VENDOR_ID) {
      throw new MiniAppError(INVALID_ARGUMENT, 'LINE identity requires a LINE session');
    }
    const binding = session.getBinding<LineBinding>();
    return binding.getAppState()?.liffId;
  }

  /** 独立触发与容器自动认证共用同一账号协调器；不向宿主返回凭据。 */
  async login(context: common.UIAbilityContext): Promise<void> {
    await this.requestLogin(context).result;
  }

  /** Binding 持有自己的取消句柄，释放一个容器不会取消其他等待者。 */
  requestLogin(context: common.UIAbilityContext): LineLoginRequest {
    if (this.mode !== LineMode.CLIENT) {
      const request: LineLoginRequest = {
        result: Promise.resolve(), cancel: (): void => {
        }
      };
      return request;
    }
    const account = this.getAccount() ?? LineDefaultAccount.get(context);
    return LineLoginCoordinator.forAccount(account).request(new LineLoginDialogHost(context),
      this.host?.loginPolicy === 'reuseOnly');
  }

  async register(context: common.UIAbilityContext): Promise<void> { await this.requestRegistration(context).result; }

  requestRegistration(context: common.UIAbilityContext): LineRegistrationRequest {
    if (this.mode !== LineMode.CLIENT) {
      return { result: Promise.reject(new MiniAppError(LineErrorCode.REGISTRATION_UNSUPPORTED, 'LINE registration requires client mode')), cancel: (): void => {} };
    }
    const account = this.getAccount() ?? LineDefaultAccount.get(context);
    return LineLoginCoordinator.forAccount(account).requestRegistration(new LineRegistrationDialogHost(context));
  }

  createNavigationController(): LineNavigationController {
    return new LineNavigationController();
  }

  reportSubWindowError(error: MiniAppError): void {
    this.host?.onSubWindowError?.(error);
  }
}
