import { BridgeContext } from '../../../core/Runtime';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';
import { VkTestBannerController, VkTestBannerResult } from '../testing/VkTestBannerController';

interface ShowBannerParams {
  banner_location?: string;
  layout_type?: string;
  can_close?: boolean;
}

/** 只由 Debug 显式开关注册；不得用作真实 VK 广告失败的降级成功。 */
export class VkTestBannerHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly banner: VkTestBannerController;

  constructor(context: BridgeContext, banner: VkTestBannerController) {
    this.context = context;
    this.banner = banner;
  }

  @VkEvent({ name: 'VKWebAppCheckBannerAd' })
  async check(params: object): Promise<VkTestBannerResult> {
    ParamAssert.assertObject(params, 'params');
    return this.banner.check();
  }

  @VkEvent({ name: 'VKWebAppShowBannerAd' })
  async show(params: ShowBannerParams): Promise<VkTestBannerResult> {
    ParamAssert.assertObject(params, 'params');
    if (params.banner_location !== undefined) {
      ParamAssert.assertEnum(params.banner_location, 'banner_location', ['top', 'bottom']);
    }
    if (params.layout_type !== undefined) {
      ParamAssert.assertEnum(params.layout_type, 'layout_type', ['resize', 'overlay']);
    }
    ParamAssert.assertOptionalBoolean(params.can_close, 'can_close');
    const location = params.banner_location ?? 'bottom';
    const layout = location === 'top' ? 'resize' : (params.layout_type ?? 'resize');
    return this.banner.show(location, layout, params.can_close ?? true);
  }

  @VkEvent({ name: 'VKWebAppHideBannerAd' })
  async hide(params: object): Promise<VkTestBannerResult> {
    ParamAssert.assertObject(params, 'params');
    return this.banner.hide();
  }

  dispose(): void {
    this.banner.dispose();
  }
}
