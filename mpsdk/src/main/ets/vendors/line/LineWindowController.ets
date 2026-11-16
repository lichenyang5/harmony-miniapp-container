import { LineRpcTimeout } from './network/LineRpcConstants';
import { LineErrorCode } from './LineErrorCode';
import { url } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { MiniAppSession } from '../../core/Runtime';
import { MiniAppError } from '../../core/MiniAppError';
import { MiniAppInfo } from '../../core/MiniAppOptions';
import { LineAdapter } from './LineAdapter';
import { LINE_VENDOR_ID } from './LineConstants';
import { createLineLiffHeaders } from './liff/LineLiffHeaders';
import { LineLiffViewResult, LineSubViewLaunch, LineSubViewRequest, LineSubWindowResultRequest } from './liff/LineLiffTypes';
import { SdkLogger } from '../../logging/SdkLogger';
import { LineConsentController } from './liff/LineConsentController';
import { LineSubViewPresentation } from './liff/LineSubViewPresentation';

/** LINE 专用视图宿主，不进入公共 Session 的多窗口契约。 */
export interface LineWindowHost {
  show: (session: MiniAppSession, headers: webview.WebHeader[], presentation?: LineSubViewPresentation) =>
    void | Promise<void>;
  hide: () => void;
  reportError: (error: MiniAppError) => void;
}

/** 协议控制器只描述子窗口；具体 Vendor/Session 由组装处创建。 */
export type LineChildSessionFactory =
  (id: string, info: MiniAppInfo, launch: LineSubViewLaunch) => MiniAppSession;

export class LineWindowController {
  private host?: LineWindowHost;
  private child?: MiniAppSession;
  private generation: number = 0;
  private opening: boolean = false;
  private disposed: boolean = false;
  private storeResult?: () => Promise<void>;
  private readonly parent: MiniAppSession;
  private readonly adapter: LineAdapter;
  private readonly createChild: LineChildSessionFactory;
  private readonly consent?: LineConsentController;

  constructor(parent: MiniAppSession, adapter: LineAdapter, createChild: LineChildSessionFactory,
    consent?: LineConsentController) {
    this.parent = parent;
    this.adapter = adapter;
    this.createChild = createChild;
    this.consent = consent;
  }

  private static launchUrl(launch: LineSubViewLaunch, requestedUrl: string): string {
    const view = launch.result;
    const endpoint = new url.URL(view.url);
    const requested = new url.URL(requestedUrl);
    requested.params.forEach((value: string, key: string): void => {
      if (key === 'liff.domain' || key === 'liff.referrer') {
        return;
      }
      if (key === 'liff.state') {
        if (!value || value === '/') {
          return;
        }
        const state = new url.URL(value, 'https://liff-state.invalid');
        state.params.delete('liff.preferCachedInstance');
        value = state.pathname + state.search + state.hash;
        if (value === '/') {
          return;
        }
      }
      endpoint.params.set(key, value);
    });
    const address: string = endpoint.toString();
    const separator = address.includes('#') ? '&' : '#';
    // APK fragment 字段不逐值编码；值由已验证的服务响应与本次 MST 上下文提供。
    return address + separator +
      `context_token=${view.contextToken ?? ''}&access_token=${view.accessToken ?? ''}` +
      `&feature_token=${view.featureToken ?? ''}&id_token=${view.idToken ?? ''}` +
      `&client_id=${view.clientId ?? ''}&mst_verifier=${launch.verifier}&msit=${launch.msit}` +
      `&liff.hide_close_button_in_subwindow=${view.hideCloseButton === true}`;
  }

  attach(host: LineWindowHost): void {
    if (this.disposed) {
      return;
    }
    this.host = host;
  }

  detach(host: LineWindowHost): void {
    if (this.host !== host) {
      return;
    }
    this.reset();
    this.host = undefined;
  }

  open(address: string, verifier: string): void {
    if (this.disposed) {
      return;
    }
    if (this.child || this.opening) {
      this.report(new MiniAppError(LineErrorCode.SUBWINDOW_BUSY, '已有 LINE 子窗口正在打开或运行'));
      return;
    }
    let request: LineSubViewRequest;
    try {
      const command = new url.URL(address);
      const targetAddress = command.params.get('url');
      const msit = command.params.get('msit');
      if (command.pathname !== '' && command.pathname !== '/') {
        throw new Error('path');
      }
      if (!targetAddress || !msit) {
        throw new Error('arguments');
      }
      const target = new url.URL(targetAddress);
      if (target.protocol !== 'https:' || target.username || target.password ||
        (target.hostname !== 'liff.line.me' && target.hostname !== 'miniapp.line.me')) {
        throw new Error('target');
      }
      const liffId = decodeURIComponent(target.pathname.split('/')[1]);
      if (!liffId || liffId.includes('/')) {
        throw new Error('id');
      }
      request = {
        liffId,
        msit,
        requestedUrl: targetAddress,
        domain: target.hostname
      };
      if (!this.host) {
        throw new MiniAppError(LineErrorCode.WINDOW_HOST_REQUIRED, 'LINE 子窗口视图尚未绑定');
      }
    } catch (error) {
      this.report(MiniAppError.from(error as Object, LineErrorCode.SUBWINDOW_INVALID, 'LINE 子窗口地址或参数无效'));
      return;
    }
    this.opening = true;
    SdkLogger.info('LineWindow', 'opening', {
      sessionId: this.parent.id,
      documentId: this.parent.getDocumentId(), code: 'NATIVE_AUTH'
    });
    const generation = ++this.generation;
    const documentId = this.parent.getDocumentId();
    this.prepare(request, verifier, generation, documentId);
  }

  /** 原生关闭与 APK finish 一致：先移除子窗口，再异步完成原生结果收尾。 */
  requestClose(): boolean {
    if (!this.child) {
      return this.opening;
    }
    this.reset();
    return true;
  }

  /** 父页面切换或关闭使整条子窗口链路失效，不向新页面交付旧结果。 */
  reset(): void {
    this.generation++;
    this.consent?.cancel();
    this.opening = false;
    const child = this.child;
    const storeResult = this.storeResult;
    this.child = undefined;
    this.storeResult = undefined;
    child?.close();
    if (child) {
      try {
        this.host?.hide();
      } catch (_) {
        SdkLogger.warn('LineWindow', 'hideFailed', { sessionId: this.parent.id });
      }
      if (storeResult) {
        // 清除窗口状态后再提交；迟到失败不操作宿主或下一次打开的窗口。
        storeResult().catch((error: Object): void => {
          const failure = MiniAppError.from(error, LineErrorCode.SUBWINDOW_CLOSE_FAILED, 'LINE 子窗口结果收尾失败');
          SdkLogger.warn('LineWindow', 'resultStoreFailed', { sessionId: child.id, code: failure.code });
        });
      }
    }
  }

  fail(error: MiniAppError): void {
    this.reset();
    this.report(error);
  }

  dispose(): void {
    this.disposed = true;
    this.reset();
    this.host = undefined;
  }

  private async prepare(request: LineSubViewRequest, verifier: string,
    generation: number, documentId: number): Promise<void> {
    try {
      const account = this.adapter.getAccount();
      const accountVersion: number | undefined = account?.getVersion();
      const issue = (): Promise<LineLiffViewResult> => this.issueWithTimeout(request);
      const result: LineLiffViewResult = await (account && this.consent ?
        this.consent.run(account, issue) : issue());
      if (this.disposed || generation !== this.generation || documentId !== this.parent.getDocumentId()) {
        return;
      }
      if (accountVersion !== account?.getVersion()) {
        throw new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE 账号已切换');
      }
      const launch: LineSubViewLaunch = {
        liffId: result.liffId ?? request.liffId,
        msit: request.msit,
        verifier,
        result,
        onClose: (): void => {
          if (this.generation === generation) {
            this.reset();
          }
        }
      };
      const info: MiniAppInfo = {
        appId: request.liffId,
        vendor: LINE_VENDOR_ID,
        url: LineWindowController.launchUrl(launch, request.requestedUrl),
        customUserAgent: (this.parent.info.customUserAgent ?? 'Mozilla/5.0 Line/26.15.1 LIFF')
          .replace(/LIFF\/SubWindow/g, 'LIFF') + ' LIFF/SubWindow',
        isOpenDomStorage: true,
        isOpenGeolocation: this.parent.info.isOpenGeolocation
      };
      const child = this.createChild(`${this.parent.id}-line-sub-${generation}`, info, launch);
      this.child = child;
      const resultRequest: LineSubWindowResultRequest = {
        liffId: launch.liffId, msit: request.msit, mstVerifier: verifier
      };
      this.storeResult = async (): Promise<void> => {
        if (account !== this.adapter.getAccount() || accountVersion !== account?.getVersion()) {
          throw new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE 账号已切换或退出');
        }
        await this.adapter.storeSubWindowResult(resultRequest);
      };
      const presentation: LineSubViewPresentation = {
        presentationType: result.presentationType,
        closeButtonPosition: result.closeButtonPosition,
        closeButtonLabel: result.closeButtonLabel,
        hideCloseButton: result.hideCloseButton
      };
      await this.host?.show(child, createLineLiffHeaders(result.accessToken), presentation);
      if (this.child === child && generation === this.generation) {
        SdkLogger.info('LineWindow', 'shown', {
          sessionId: child.id, documentId,
          code: 'NATIVE_AUTH'
        });
      }
    } catch (error) {
      if (!this.disposed && generation === this.generation && documentId === this.parent.getDocumentId()) {
        this.reset();
        this.report(MiniAppError.from(error as Object, LineErrorCode.SUBWINDOW_FAILED, '打开 LINE 子窗口失败'));
      }
    } finally {
      if (generation === this.generation) {
        this.opening = false;
      }
    }
  }

  /** 30 秒只限制单次发行 RPC，不包含用户阅读和操作官方授权页的时间。 */
  private async issueWithTimeout(request: LineSubViewRequest): Promise<LineLiffViewResult> {
    let timer: number = -1;
    const expired = new Promise<LineLiffViewResult>((_resolve, reject): void => {
      timer = setTimeout((): void => {
        reject(new MiniAppError(LineErrorCode.SUBVIEW_TIMEOUT, '申请 LINE 子视图超时'));
      }, LineRpcTimeout.SUBVIEW_MS);
    });
    try {
      return await Promise.race([this.adapter.issueSubLiffView(request), expired]);
    } finally {
      clearTimeout(timer);
    }
  }

  private report(error: MiniAppError): void {
    SdkLogger.warn('LineWindow', 'operationFailed', { sessionId: this.parent.id, code: error.code });
    try {
      this.host?.reportError(error);
    } catch (_) {
      SdkLogger.warn('LineWindow', 'errorNotificationFailed', { sessionId: this.parent.id });
    }
  }
}
