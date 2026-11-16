import { VK_VENDOR_ID } from '../VkVendor';
import { BridgeContext } from '../../../core/Runtime';
import { MiniAppError } from '../../../core/MiniAppError';
import {
  CAPABILITY_ALREADY_REGISTERED_OR_INVALID,
  SESSION_CLOSED,
  VENDOR_LIFECYCLE_FAILED
} from '../../../core/MiniAppErrorCode';
import { SdkLogger } from '../../../logging/SdkLogger';
import { BaseVkEventHandler } from './BaseVkEventHandler';
import { getVkEventHandlers, VkEventRegistration } from './VkEvent';
import { getVkResponseInterceptors } from './VkResponse';
import { VkResponseCallback } from './VkResponseCallback';
import { ParamAssert } from '../../../utils/ParamAssert';
import { ResourceUtils } from '../../../utils/ResourceUtils';
import { VkBridgeProtocol } from '../VkBridgeProtocol';

interface VkSupportedHandlersFile {
  version: number;
  supportedHandlers: string[];
  unsupportedHandlers?: string[];
}

const TAG: string = 'VkEventRegistry';

/** 每个 VkBinding 独占一个注册表；业务 appId 相同的会话也互不共享。 */
export class VkEventRegistry {
  private static presetSupportedHandlers?: string[];
  private static presetUnsupportedHandlers: Set<string> = new Set<string>();
  private readonly context: BridgeContext;
  private instances: BaseVkEventHandler[] = [];
  private eventHandlers = new Map<string, VkEventRegistration>();
  private responseInterceptors = new Map<string, VkResponseCallback>();
  private disposed: boolean = false;
  private presetHandlers: string[];
  private remoteHandlers: string[] = [];

  constructor(context: BridgeContext) {
    this.context = context;
    this.presetHandlers = VkEventRegistry.getPresetSupportedHandlers(context);
    SdkLogger.info(TAG, 'registryCreated', { sessionId: context.id, vendorId: VK_VENDOR_ID });
  }

  /** @internal 进程内读取一次，返回副本，不保存任何页面的远端名单。 */
  private static getPresetSupportedHandlers(context: BridgeContext): string[] {
    if (VkEventRegistry.presetSupportedHandlers === undefined) {
      try {
        const text: string = ResourceUtils.readText(context.uiAbilityContext.resourceManager,
          'vk/supported-handlers.json');
        const file: VkSupportedHandlersFile = JSON.parse(text) as VkSupportedHandlersFile;
        ParamAssert.assertStringArray(file.supportedHandlers, 'supportedHandlers');
        if (file.unsupportedHandlers !== undefined) {
          ParamAssert.assertStringArray(file.unsupportedHandlers, 'unsupportedHandlers');
        }
        VkEventRegistry.presetSupportedHandlers = Array.from(new Set<string>(file.supportedHandlers));
        VkEventRegistry.presetUnsupportedHandlers = new Set<string>(file.unsupportedHandlers ?? []);
      } catch (_) {
        VkEventRegistry.presetSupportedHandlers = ['VKWebAppInit', 'VKWebAppGetConfig', 'VKWebAppGetUserInfo'];
        SdkLogger.warn(TAG, 'supportedHandlersPresetFallback', {
          sessionId: context.id, vendorId: VK_VENDOR_ID, code: 'VK_SUPPORTED_HANDLERS_PRESET_INVALID'
        });
      }
    }
    return VkEventRegistry.presetSupportedHandlers.slice();
  }

  /** 只允许所属会话使用未释放的注册表。 */
  isActiveFor(context: BridgeContext): boolean {
    return !this.disposed && this.context === context;
  }

  getHandler(event: string): VkEventRegistration | undefined {
    return this.eventHandlers.get(event);
  }

  getSupportedHandlers(): string[] {
    return Array.from(this.eventHandlers.keys());
  }

  /** 预制、实际注册和当前页面的远端名单使用相同合并规则。 */
  getAvailableHandlers(): string[] {
    if (this.disposed) {
      return [];
    }
    return VkBridgeProtocol.mergeSupportedHandlers(
      VkBridgeProtocol.mergeSupportedHandlers(this.presetHandlers, this.getSupportedHandlers()),
      this.remoteHandlers).filter((name: string): boolean => !VkEventRegistry.presetUnsupportedHandlers.has(name));
  }

  updateRemoteSupportedHandlers(handlers: string[]): void {
    this.assertOpen();
    this.remoteHandlers = handlers.slice();
  }

  getResponseInterceptor<TData extends object = object>(type: string): VkResponseCallback<TData> | undefined {
    return this.responseInterceptors.get(type) as VkResponseCallback<TData> | undefined;
  }

  registerEventHandler(name: string, handler: VkEventRegistration): void {
    this.assertOpen();
    this.assertAvailable(name);
    this.eventHandlers.set(name, handler);
    SdkLogger.debug(TAG, 'eventRegistered', {
      sessionId: this.context.id, vendorId: VK_VENDOR_ID, capability: name
    });
  }

  /** 两类注解整批校验后再注册并接管实例；重复提交同一实例不会重复注册。 */
  initHandler(handlers: BaseVkEventHandler[]): void {
    this.assertOpen();
    const pending = new Map<string, VkEventRegistration>();
    const pendingResponses = new Map<string, VkResponseCallback>();
    const instances: BaseVkEventHandler[] = [];
    handlers.forEach((handler: BaseVkEventHandler): void => {
      if (this.instances.indexOf(handler) >= 0 || instances.indexOf(handler) >= 0) {
        return;
      }
      if (handler.context !== this.context) {
        throw new MiniAppError(CAPABILITY_ALREADY_REGISTERED_OR_INVALID, 'VK 模块上下文不匹配');
      }
      let eventHandlers: Map<string, VkEventRegistration>;
      try {
        eventHandlers = getVkEventHandlers(handler);
      } catch (error) {
        throw new MiniAppError(CAPABILITY_ALREADY_REGISTERED_OR_INVALID, 'VK 事件配置无效', error);
      }
      eventHandlers.forEach((registration: VkEventRegistration, name: string): void => {
        this.assertAvailable(name);
        if (pending.has(name)) {
          throw new MiniAppError(CAPABILITY_ALREADY_REGISTERED_OR_INVALID, 'VK 事件重复注册');
        }
        pending.set(name, registration);
      });
      getVkResponseInterceptors(handler).forEach((method: VkResponseCallback, name: string): void => {
        if (this.responseInterceptors.has(name) || pendingResponses.has(name)) {
          SdkLogger.warn(TAG, 'responseRegistrationRejected', {
            sessionId: this.context.id,
            vendorId: VK_VENDOR_ID,
            capability: name,
            code: CAPABILITY_ALREADY_REGISTERED_OR_INVALID
          });
          throw new MiniAppError(CAPABILITY_ALREADY_REGISTERED_OR_INVALID, 'VK 响应拦截器重复注册');
        }
        pendingResponses.set(name, method);
      });
      instances.push(handler);
    });
    pending.forEach((registration: VkEventRegistration, name: string): void => {
      this.registerEventHandler(name, registration);
    });
    pendingResponses.forEach((method: VkResponseCallback, name: string): void => {
      this.responseInterceptors.set(name, method);
      SdkLogger.debug(TAG, 'responseRegistered', {
        sessionId: this.context.id, vendorId: VK_VENDOR_ID, capability: name
      });
    });
    this.instances.push(...instances);
    SdkLogger.info(TAG, 'handlersInitialized', {
      sessionId: this.context.id, vendorId: VK_VENDOR_ID, count: this.eventHandlers.size
    });
  }

  dispose(): void {
    this.remoteHandlers = [];
    this.presetHandlers = [];
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    const instances = this.instances;
    this.instances = [];
    this.eventHandlers.clear();
    this.responseInterceptors.clear();
    instances.forEach((handler: BaseVkEventHandler): void => {
      try {
        handler.dispose();
      } catch (_) {
        SdkLogger.warn(TAG, 'disposeFailed', {
          sessionId: this.context.id, vendorId: VK_VENDOR_ID, code: VENDOR_LIFECYCLE_FAILED
        });
      }
    });
    SdkLogger.info(TAG, 'registryDisposed', {
      sessionId: this.context.id, vendorId: VK_VENDOR_ID, count: instances.length
    });
  }

  private assertOpen(): void {
    if (this.disposed) {
      throw new MiniAppError(SESSION_CLOSED, 'VK 事件注册表已关闭');
    }
  }

  private assertAvailable(name: string): void {
    if (name.trim().length === 0 || this.eventHandlers.has(name)) {
      SdkLogger.warn(TAG, 'registrationRejected', {
        sessionId: this.context.id,
        vendorId: VK_VENDOR_ID,
        capability: name,
        code: CAPABILITY_ALREADY_REGISTERED_OR_INVALID
      });
      throw new MiniAppError(CAPABILITY_ALREADY_REGISTERED_OR_INVALID, 'VK 事件名为空或重复');
    }
  }
}
