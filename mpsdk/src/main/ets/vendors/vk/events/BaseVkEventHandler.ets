import { BridgeContext } from '../../../core/Runtime';

/** 由绑定创建、注册表持有和释放的装饰器模块。 */
export interface BaseVkEventHandler {
  readonly context: BridgeContext;

  dispose(): void;
}

