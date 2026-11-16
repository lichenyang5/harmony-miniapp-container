import { BridgeContext } from '../../core/Runtime';
import { LineEventContext } from './LineEventContext';

/** 单会话业务处理器；批量注册成功后由注册表持有并释放。 */
export interface LineEventHandler<TData extends object = object> {
  readonly context: BridgeContext;
  readonly type: string;
  readonly ext: boolean;

  handle(params: object, request: LineEventContext): Promise<TData | undefined>;

  dispose(): void;
}
