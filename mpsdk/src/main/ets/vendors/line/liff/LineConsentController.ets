import { MiniAppError } from '../../../core/MiniAppError';
import { LineAccountManager } from '../auth/LineAccountManager';
import { LineErrorCode } from '../LineErrorCode';
import { LineLiffViewResult } from './LineLiffTypes';
import { LineConsentRequiredError } from './LineConsentRequiredError';
import { SdkLogger } from '../../../logging/SdkLogger';

import { LineConsentPresenter, LineConsentRequest } from '../consent/LineConsentTypes';

/** 所属 LINE 会话的发行恢复器；主、子视图共用，账号认证成功状态不受授权取消影响。 */
export class LineConsentController {
  private readonly presenter: LineConsentPresenter;
  private generation: number = 0;
  private pending?: LineConsentRequest;

  constructor(presenter: LineConsentPresenter) {
    this.presenter = presenter;
  }

  cancel(): void {
    this.generation++;
    const pending = this.pending;
    this.pending = undefined;
    pending?.cancel();
  }

  async run(account: LineAccountManager,
    issue: () => Promise<LineLiffViewResult>): Promise<LineLiffViewResult> {
    const generation: number = this.generation;
    const accountVersion: number = account.getVersion();
    try {
      // 无授权页的普通成功路径仍由原发行调用者执行其既有会话/账号交付检查。
      return await issue();
    } catch (error) {
      if (!(error instanceof LineConsentRequiredError)) {
        throw MiniAppError.from(error as Object, LineErrorCode.LIFF_FAILED, 'LINE 视图发行失败');
      }
      this.assertCurrent(generation, account, accountVersion);
      if (this.pending) {
        throw new MiniAppError(LineErrorCode.CONSENT_BUSY, 'LINE 授权正在进行');
      }
      SdkLogger.info('LineConsent', 'opening');
      const request: LineConsentRequest = this.presenter.request({
        url: error.consentUrl, headers: account.getWebAuthHeaders()
      });
      this.pending = request;
      const invalidated = (): void => {
        request.cancel();
      };
      account.addInvalidationListener(invalidated);
      try {
        if (!await request.result) {
          throw new MiniAppError(LineErrorCode.CONSENT_CANCELLED, 'LINE consent cancelled');
        }
      } catch (error) {
        const failure = MiniAppError.from(error as Object, LineErrorCode.CONSENT_UI_FAILED, 'LINE 授权页面失败');
        SdkLogger.warn('LineConsent', 'failed', { code: failure.code });
        throw failure;
      } finally {
        account.removeInvalidationListener(invalidated);
        if (this.pending === request) {
          this.pending = undefined;
        }
      }
      this.assertCurrent(generation, account, accountVersion);
      // APK 返回 RESULT_OK 后重新发行。第二次仍要求授权则直接返回，不能无限弹窗。
      const result = await issue();
      this.assertCurrent(generation, account, accountVersion);
      SdkLogger.info('LineConsent', 'viewReissued');
      return result;
    }
  }

  private assertCurrent(generation: number, account: LineAccountManager, version: number): void {
    if (generation !== this.generation || account.getVersion() !== version) {
      throw new MiniAppError(LineErrorCode.CONSENT_CANCELLED, 'LINE 授权已取消或账号已切换');
    }
  }
}
