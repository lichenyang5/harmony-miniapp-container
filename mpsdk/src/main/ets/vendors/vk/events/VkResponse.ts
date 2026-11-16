import { InterceptResult } from '../InterceptResult';

// TS 只负责装饰器元数据；具体事件类型由 ArkTS 的 VkResponseCallback 约束。
type ResponseMethod<TEvent extends object = object> = (event: TEvent) => InterceptResult;

interface VkResponseMetadata {
  name: string;
  method: ResponseMethod;
}

interface VkResponseMethodDescriptor<TData extends object> {
  value?: ResponseMethod<TData>;
}

const responseMetadata = new WeakMap<object, VkResponseMetadata[]>();

/** 类定义阶段只记录元数据；参数类型从同步方法签名推断。 */
export function VkResponse(name?: string) {
  return <TData extends object>(target: object, propKey: string,
    descriptor: VkResponseMethodDescriptor<TData>): void => {
    if (!descriptor.value) {
      throw new Error('VK response decorator requires an instance method');
    }
    const responses = responseMetadata.get(target) ?? [];
    responses.push({ name: name ?? propKey, method: descriptor.value as ResponseMethod });
    responseMetadata.set(target, responses);
  };
}

export function getVkResponseInterceptors(instance: object): Map<string, ResponseMethod> {
  const handlers = new Map<string, ResponseMethod>();
  const responses = responseMetadata.get(Object.getPrototypeOf(instance)) ?? [];
  responses.forEach((response) => {
    if (!response.name.trim() || handlers.has(response.name)) {
      throw new Error('Duplicate or empty VK response type');
    }
    handlers.set(response.name, response.method.bind(instance));
  });
  return handlers;
}
