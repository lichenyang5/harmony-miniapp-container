import { BridgeContext } from '../../../core/Runtime';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';
import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import { VkTestNativeAdController, VkTestNativeAdResult } from '../testing/VkTestNativeAdController';

interface NativeAdsParams {
  ad_format: string;
  use_waterfall?: boolean;
}

/** 显式 Debug 本地插屏测试，不提供 VK 素材、激励完成或奖励凭证。 */
export class VkTestNativeAdsHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly ad: VkTestNativeAdController;

  constructor(context: BridgeContext, ad: VkTestNativeAdController) {
    this.context = context;
    this.ad = ad;
  }

  @VkEvent({ name: 'VKWebAppCheckNativeAds' })
  async check(params: NativeAdsParams): Promise<VkTestNativeAdResult> {
    this.validate(params);
    return params.ad_format === 'interstitial' ? this.ad.check() : { result: false };
  }

  @VkEvent({ name: 'VKWebAppShowNativeAds' })
  async show(params: NativeAdsParams): Promise<VkTestNativeAdResult> {
    this.validate(params);
    if (params.ad_format !== 'interstitial') {
      throw VkBridgeError.client(VkClientErrorCode.UNSUPPORTED_PLATFORM,
        'Local test mode supports interstitial ads only');
    }
    return this.ad.show();
  }

  dispose(): void {
    this.ad.dispose();
  }

  private validate(params: NativeAdsParams): void {
    ParamAssert.assertObject(params, 'params');
    ParamAssert.assertEnum(params.ad_format, 'ad_format', ['interstitial', 'reward']);
    ParamAssert.assertOptionalBoolean(params.use_waterfall, 'use_waterfall');
  }
}
