import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import { BridgeContext } from '../../../core/Runtime';
import { AuthTokenRequest, AuthTokenResult, VkAdapter } from '../VkAdapter';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';

export const VK_WEB_APP_GET_AUTH_TOKEN: string = 'VKWebAppGetAuthToken';

export interface VkAuthTokenParams {
  app_id: number;
  scope: string;
}

export interface VkAuthTokenResult {
  access_token: string;
  scope: string;
}

/** 将 VK 授权请求交给当前会话宿主，并转换为官方字段格式。 */
export class VkAuthTokenHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly adapter: VkAdapter;
  private disposed: boolean = false;

  constructor(context: BridgeContext, adapter: VkAdapter) {
    this.context = context;
    this.adapter = adapter;
  }

  @VkEvent({
    name: VK_WEB_APP_GET_AUTH_TOKEN,
    resultEvent: 'VKWebAppAccessTokenReceived',
    failureEvent: 'VKWebAppAccessTokenFailed'
  })
  async getAuthToken(params: VkAuthTokenParams): Promise<VkAuthTokenResult> {
    this.assertOpen();
    ParamAssert.assertObject(params, 'params');
    ParamAssert.assertNumber(params.app_id, 'app_id');
    ParamAssert.assertString(params.scope, 'scope');
    try {
      if (!Number.isSafeInteger(params.app_id) || params.app_id <= 0) {
        throw VkBridgeError.client(VkClientErrorCode.INVALID_PARAMS);
      }
      const request: AuthTokenRequest = {
        appId: params.app_id,
        scope: params.scope
      };
      const token: AuthTokenResult = await this.adapter.requestAuthToken(request);
      this.assertOpen();
      return {
        access_token: token.accessToken,
        scope: token.scope
      };
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  dispose(): void {
    this.disposed = true;
  }

  private assertOpen(): void {
    if (this.disposed) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
  }
}
