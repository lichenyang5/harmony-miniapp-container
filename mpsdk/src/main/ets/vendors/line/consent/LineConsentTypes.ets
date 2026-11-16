/** 官方授权页的展示参数，不属于 LIFF 发行或网页 OAuth 的业务结果。 */
export interface LineConsentPage {
  url: string;
  headers: Record<string, string>;
}

export interface LineConsentRequest {
  /** 弹层关闭后交付允许／拒绝；技术失败和外部取消通过 reject 结束。 */
  result: Promise<boolean>;
  cancel: () => void;
}

export interface LineConsentPresenter {
  request(page: LineConsentPage): LineConsentRequest;
}
