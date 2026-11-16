/** 当前小程序网页媒体暂停调用，不包含 VK 协议字段。 */
export type AudioPauseInvoker = () => void;

/** VK 音频暂停处理器依赖的原生能力。 */
export interface AudioPauseProvider {
  pause(): Promise<void>;
}

/** 只调用当前 ArkWeb 的媒体暂停能力，不识别 VK 方法名。 */
export class AudioTools implements AudioPauseProvider {
  private readonly invokePause: AudioPauseInvoker;

  constructor(invokePause: AudioPauseInvoker) {
    this.invokePause = invokePause;
  }

  async pause(): Promise<void> {
    this.invokePause();
  }
}
