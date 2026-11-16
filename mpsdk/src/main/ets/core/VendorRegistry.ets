import { Vendor } from './Runtime';
import { VkVendor } from '../vendors/vk/VkVendor';
import { LineVendor } from '../vendors/line/LineVendor';


/** 内置厂商目录；方法实现及原生工具由厂商注入对象管理。 */
export class VendorRegistry {
  private vendors: Map<string, Vendor> = new Map();

  /** 初始化内置厂商。 */
  constructor() {
    const vk = new VkVendor();
    this.vendors.set(vk.vendorId, vk);
    const line = new LineVendor();
    this.vendors.set(line.vendorId, line);
  }

  /** 按厂商标识查询共享定义，未内置时返回 undefined。 */
  get(vendorId: string): Vendor | undefined {
    return this.vendors.get(vendorId);
  }
}
