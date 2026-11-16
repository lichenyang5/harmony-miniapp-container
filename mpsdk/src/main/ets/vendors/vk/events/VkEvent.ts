import { VkEventCallback } from './VkEventCallback';

export const DEFAULT_VK_EVENT_TIMEOUT: number = 30000;

export interface VkEventOptions {
  name: string;
  timeout?: number;
  resultEvent?: string;
  failureEvent?: string;
}

export interface VkEventRegistration {
  callback: VkEventCallback;
  timeout: number;
  resultEvent: string;
  failureEvent: string;
}

interface VkEventMetadata {
  options: VkEventOptions;
  method: VkEventCallback;
}

// 只约束装饰器实际读取的 value，允许方法返回更具体的业务结果类型。
interface VkEventMethodDescriptor<TParams extends object> {
  value?: VkEventCallback<TParams>;
}

// 原型访问和函数绑定集中在 TypeScript 中，避免 ArkTS 的动态语法限制。
const eventMetadata = new WeakMap<object, VkEventMetadata[]>();

function resolveResponseEvent(value: string | undefined, fallback: string): string {
  if (value === undefined) {
    return fallback;
  }
  if (typeof value !== 'string') {
    throw new Error('VK response event names must be strings');
  }
  return value.trim().length === 0 ? fallback : value;
}

/** 类定义时记录元数据，不创建实例、不访问运行时上下文。 */
export function VkEvent(options: VkEventOptions) {
  // 泛型放在真正接收方法描述符的装饰器上，由方法参数类型推断。
  return <TParams extends object>(target: object, propKey: string,
    descriptor: VkEventMethodDescriptor<TParams>): void => {
    if (!descriptor.value) {
      throw new Error('VK event decorator requires an instance method');
    }
    const events = eventMetadata.get(target) ?? [];
    // 不同事件的参数类型只在注册边界擦除，业务方法仍保留各自类型。
    events.push({ options, method: descriptor.value as VkEventCallback });
    eventMetadata.set(target, events);
  };
}

export function getVkEventHandlers(instance: object): Map<string, VkEventRegistration> {
  const handlers = new Map<string, VkEventRegistration>();
  const events = eventMetadata.get(Object.getPrototypeOf(instance)) ?? [];
  events.forEach((event) => {
    const timeout: number = event.options.timeout ?? DEFAULT_VK_EVENT_TIMEOUT;
    if (!event.options.name.trim() || handlers.has(event.options.name)) {
      throw new Error('Duplicate or empty VK event name');
    }
    if (!Number.isInteger(timeout)) {
      throw new Error('VK event timeout must be an integer');
    }
    const resultEvent = resolveResponseEvent(event.options.resultEvent, event.options.name + 'Result');
    const failureEvent = resolveResponseEvent(event.options.failureEvent, event.options.name + 'Failed');
    handlers.set(event.options.name, {
      callback: event.method.bind(instance),
      timeout,
      resultEvent,
      failureEvent
    });
  });
  return handlers;
}
