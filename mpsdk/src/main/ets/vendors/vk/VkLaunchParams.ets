import { VendorBinding } from '../../core/Runtime';
import { VkMiniAppIdentity } from './VkMiniAppIdentity';

export interface VkLaunchParam {
  name: string;
  value: string;
}

/** 当前页面的启动参数快照；保留空值、重复键和顺序，不作为授权或验签依据。 */
export class VkLaunchParams {
  private entries: VkLaunchParam[] = [];
  private readonly identity: VkMiniAppIdentity;

  constructor(identity: VkMiniAppIdentity) {
    this.identity = identity;
  }

  get(name: string): string | undefined {
    return this.entries.find((entry: VkLaunchParam): boolean => entry.name === name)?.value;
  }

  getAll(name: string): string[] {
    return this.entries.filter((entry: VkLaunchParam): boolean => entry.name === name)
      .map((entry: VkLaunchParam): string => entry.value);
  }

  getEntries(): VkLaunchParam[] {
    return this.entries.map((entry: VkLaunchParam): VkLaunchParam => ({ name: entry.name, value: entry.value }));
  }

  update(hostUrl: string, dataJson: string): boolean {
    if (typeof hostUrl !== 'string' || typeof dataJson !== 'string') {
      return false;
    }
    let payload: Object;
    try {
      payload = JSON.parse(dataJson) as Object;
    } catch (_) {
      return false;
    }
    if (!Array.isArray(payload)) {
      return false;
    }
    const entries: VkLaunchParam[] = [];
    for (const item of payload as Object[]) {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        return false;
      }
      const values = item as Record<string, Object>;
      if (typeof values['name'] !== 'string' || typeof values['value'] !== 'string') {
        return false;
      }
      entries.push({ name: values['name'] as string, value: values['value'] as string });
    }
    const appId = entries.find((entry: VkLaunchParam): boolean => entry.name === 'vk_app_id')?.value;
    const userId = entries.find((entry: VkLaunchParam): boolean => entry.name === 'vk_user_id')?.value;
    const sign = entries.find((entry: VkLaunchParam): boolean => entry.name === 'sign')?.value;
    if (!appId || !userId || !sign || !this.identity.identify(hostUrl, appId)) {
      return false;
    }
    this.entries = entries;
    return true;
  }

  clear(): void {
    this.entries = [];
  }
}

/** 仅供 VK 模块读取；不向公共 Session 或 HAR API 添加厂商字段。 */
export interface VkLaunchParamsBinding extends VendorBinding {
  readonly launchParams: VkLaunchParams;
}
