import { BridgeContext } from '../../../core/Runtime';
import { MiniAppError } from '../../../core/MiniAppError';
import { NOT_SUPPORTED, SESSION_CLOSED } from '../../../core/MiniAppErrorCode';
import { LINE_CLOSE_WINDOW_METHOD } from '../LineConstants';
import { LineEventContext } from '../LineEventContext';
import { LineEventHandler } from '../LineEventHandler';

interface LineCloseWindowResult {}

/** 先提交空成功回包，再请求关闭当前容器。 */
export class LineCloseWindowHandler implements LineEventHandler<LineCloseWindowResult> {
  readonly context: BridgeContext;
  readonly type: string = LINE_CLOSE_WINDOW_METHOD;
  readonly ext: boolean = true
  private disposed: boolean = false;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  async handle(_params: object, request: LineEventContext): Promise<LineCloseWindowResult> {
    if (this.disposed) {
      throw new MiniAppError(SESSION_CLOSED, 'LINE close handler is closed');
    }
    if (!this.context.requestClose) {
      throw new MiniAppError(NOT_SUPPORTED, 'Host close is unavailable');
    }
    request.afterReplySubmitted((): void => {
      if (!this.disposed) {
        this.context.requestClose?.();
      }
    });
    return {};
  }

  dispose(): void {
    this.disposed = true;
  }
}
