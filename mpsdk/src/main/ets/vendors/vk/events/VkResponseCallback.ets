import { InterceptResult } from '../InterceptResult';
import { VkBridgeEvent } from '../VkBridgeProtocol';

/** 同步处理完整事件，直接返回交给网页的最终拦截结果。 */
export type VkResponseCallback<TData extends object = object> = (event: VkBridgeEvent<TData>) => InterceptResult;
