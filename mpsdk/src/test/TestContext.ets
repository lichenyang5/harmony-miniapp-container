import { VK_VENDOR_ID, VkVendor } from '../main/ets/vendors/vk/VkVendor';
import { common } from '@kit.AbilityKit';
import { BridgeContext, MiniAppDescriptor, MiniAppSession, SwipeBackController } from '../main/ets/core/Runtime';
import { VendorAdapter } from '../main/ets/core/VendorAdapter';
import { VkAdapter } from '../main/ets/vendors/vk/VkAdapter';

export class EmptyParams {
}

class TestSwipeBackController implements SwipeBackController {
  setEnabled(_enabled: boolean): void {
  }

  dispose(): void {
  }
}

/** 需要 Session 接口的桥接测试使用真实会话，普通 handler 测试仍使用 VkTestContext。 */
export class VkTestSession extends MiniAppSession {
  constructor(adapter: VendorAdapter = new VkAdapter()) {
    const descriptor: MiniAppDescriptor = {
      info: { appId: 'vk-handler-test-app', vendor: VK_VENDOR_ID, url: 'https://vk.ru/app1' },
      vendor: new VkVendor(),
      adapter,
      swipeBackController: new TestSwipeBackController()
    };
    super('vk-handler-test', descriptor, getTestUiAbilityContext());
  }
}

export class VkTestContext implements BridgeContext {
  readonly id: string = 'vk-handler-test';
  readonly appId: string = 'vk-handler-test-app';
  readonly vendorId: string = VK_VENDOR_ID;
  readonly uiAbilityContext: common.UIAbilityContext = getTestUiAbilityContext();

  send(_script: string): Promise<boolean> {
    return Promise.resolve(true);
  }

  getDocumentId(): number {
    return 1;
  }

  addCleanup(_cleanup: () => void): void {
  }

  closeMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  openMenu(): Promise<boolean> {
    return Promise.resolve(false);
  }

  pauseAllMedia(): void {
  }

  setSwipeBackEnabled(_enabled: boolean): void {
  }
}

/** Hypium 单元测试环境提供的 UIAbilityContext，仅供构造真实 Runtime 会话。 */
export function getTestUiAbilityContext(): common.UIAbilityContext {
  return getContext() as common.UIAbilityContext;
}
