import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import { AudioPauseProvider, AudioTools } from '../../../capabilities/audio/AudioTools';
import { BridgeContext } from '../../../core/Runtime';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';

export const VK_WEB_APP_AUDIO_PAUSE: string = 'VKWebAppAudioPause';

interface VkBooleanResult {
  result: boolean;
}

/** 将 VK 音频暂停请求转交给当前小程序 ArkWeb。 */
export class VkAudioHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly provider: AudioPauseProvider;

  constructor(context: BridgeContext, provider?: AudioPauseProvider) {
    this.context = context;
    this.provider = provider ?? new AudioTools((): void => context.pauseAllMedia());
  }

  @VkEvent({ name: VK_WEB_APP_AUDIO_PAUSE })
  async pauseAudio(params: object): Promise<VkBooleanResult> {
    try {
      await this.provider.pause();
      const result: VkBooleanResult = { result: true };
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  dispose(): void {
  }
}
