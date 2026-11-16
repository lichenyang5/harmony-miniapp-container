import { AudioPauseProvider, AudioTools } from '../../../capabilities/audio/AudioTools';
import { BridgeContext } from '../../../core/Runtime';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';
import deviceInfo from '@ohos.deviceInfo';
import { VkProfile } from '../VkProfile';
import { display } from '@kit.ArkUI';
import { SdkLogger } from '../../../logging/SdkLogger';

const TAG: string = 'VkClientHandler';

export const VK_WEB_APP_GET_CLIENT_VERSION: string = 'VKWebAppGetClientVersion';

interface VKClientVersionData {
  app: string;
  build: string;
  client_user_agent: string;
  install_referrer: string;
  is_google_services_available: boolean;
  is_new_navigation: boolean;
  platform: string;
  version: string;
  vk_client_exist: boolean;
}

export class VkClientHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly provider: AudioPauseProvider;

  constructor(context: BridgeContext, provider?: AudioPauseProvider) {
    this.context = context;
    this.provider = provider ?? new AudioTools((): void => context.pauseAllMedia());
  }

  @VkEvent({ name: VK_WEB_APP_GET_CLIENT_VERSION })
  async getClientVersion(params: object): Promise<VKClientVersionData> {
    let width = 0;
    let height = 0;
    try {
      const disp = display.getDefaultDisplaySync();
      width = disp.width;
      height = disp.height;
    } catch (error) {
      SdkLogger.warn(TAG, 'getDefaultDisplaySync failed')
    }
    return {
      app: 'vkclient',
      build: VkProfile.BUILD,
      client_user_agent: `SAK_18.1.0(com.vkontakte.android)/${VkProfile.VERSION}-${VkProfile.BUILD} (Android 12; SDK 31; arm64-v8a; ${deviceInfo.brand} ${deviceInfo.productModel}; zh; ${height}x${width})`,
      install_referrer: 'com.huawei.hmos.appgallery',
      is_google_services_available: false,
      is_new_navigation: true,
      platform: 'android',
      version: VkProfile.VERSION,
      vk_client_exist: true
    };
  }

  dispose(): void {
  }
}
