import { MiniAppError } from '../../../core/MiniAppError';
import { MiniAppLifecycle } from '../../../core/lifecycle/MiniAppLifecycle';
import { LineAdapter } from '../LineAdapter';
import { MiniAppSession } from '../../../core/Runtime';
import { LineConsentPresenter } from '../consent/LineConsentTypes';

/** 来源由所属容器指定；主子 LIFF 的文档差异由加载目标处理。 */
export type LineWebLoginSource = 'liff' | 'browser';

export interface LineWebLoginInput {
  hookedFullUrl: string;
  sessionString?: string;
}

/** 解码器保证 returnUrl / consentUrl 恰好一个有效。 */
export interface LineWebLoginResult {
  returnUrl?: string;
  consentUrl?: string;
  sessionString?: string;
  liffId?: string;
}

/** 准备阶段确定最终地址，不提前发布文档状态。 */
export interface LineWebLoginNavigation {
  readonly url: string;
  load: () => Promise<void>;
}

/** LIFF 文档与独立浏览器的实际加载边界，拥有各自的窗口有效性判断。 */
export interface LineWebLoginWindow {
  getDocumentId: () => number;
  isCurrent: (documentId: number) => boolean;
  prepare: (url: string, approved: boolean, documentId: number) => LineWebLoginNavigation;
}

interface LineWebLoginWindowOptions {
  window: LineWebLoginWindow;
  consent: LineConsentPresenter;
  onFailure: (error: MiniAppError) => void;
}

/** LIFF 的账号、身份和生命周期统一从所属会话取得。 */
export interface LineLiffWebLoginOptions extends LineWebLoginWindowOptions {
  source: 'liff';
  session: MiniAppSession;
}

/** 普通浏览器不属于 LIFF 会话，独立提供账号与生命周期。 */
export interface LineBrowserWebLoginOptions extends LineWebLoginWindowOptions {
  source: 'browser';
  adapter: LineAdapter;
  lifecycle: MiniAppLifecycle;
}

export type LineWebLoginOptions = LineLiffWebLoginOptions | LineBrowserWebLoginOptions;
