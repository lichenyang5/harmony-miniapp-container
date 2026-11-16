import { VK_VENDOR_ID } from '../VkVendor';
import { BridgeContext, MiniAppSession } from '../../../core/Runtime';
import { SdkLogger } from '../../../logging/SdkLogger';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEventRegistry } from '../events/VkEventRegistry';
import { VkResponse } from '../events/VkResponse';
import { InterceptResult } from '../InterceptResult';
import { VkBridgeEvent } from '../VkBridgeProtocol';
import { BridgeRequestId } from '../JsonObjectReader';

const TAG: string = 'VkResponseInterceptor';

interface VkLaunchParamsData {
  vk_platform?: string;
  vk_language?: string;
}

interface VkSupportedHandlersData {
  supportedHandlers: string[];
}

interface VkWebGroupInfoData {
  id: number;
  name: string;
  screen_name: string;
  description?: string;
  members_count?: number;
  type: string;
  is_closed: number;
  photo_50: string;
  photo_100: string;
  photo_200: string;
  request_id?: BridgeRequestId;
  group?: object;
  result?: object[];
}

type VkGroupClosedState = 'OPEN' | 'CLOSED' | 'PRIVATE';
const GROUP_CLOSED_STATES: VkGroupClosedState[] = ['OPEN', 'CLOSED', 'PRIVATE'];

interface VkAndroidGroupInfo {
  description?: string;
  id: number;
  is_closed: VkGroupClosedState;
  members_count?: number;
  name: string;
  photo_100: string;
  photo_200: string;
  photo_50: string;
  screen_name: string;
  type: string;
}

interface VkGroupInfoResultData {
  group: VkAndroidGroupInfo;
  request_id?: BridgeRequestId;
}

/** VK 响应适配，与请求 handler 一起注册、一起释放。 */
export class VkResponseInterceptor implements BaseVkEventHandler {
  readonly session: MiniAppSession;
  readonly context: BridgeContext;
  private readonly registry: VkEventRegistry;

  constructor(session: MiniAppSession, registry: VkEventRegistry) {
    this.session = session;
    this.context = session;
    this.registry = registry;
  }

  @VkResponse('VKWebAppGetLaunchParamsResult')
  getLaunchParams(event: VkBridgeEvent<VkLaunchParamsData>): InterceptResult {
    ParamAssert.assertObject(event.data, 'data');
    /* 暂时先注释掉VKWebAppGetLaunchParamsResult回包的字段结果替换
    VKWebAppGetLaunchParamsResult返回的sign是vk服务端根据不同平台的登录access_token返回对应的sign，
    sign是和access_token的平台的真实实际LaunchParams一一对应相绑定的，替换字段值会破坏原本的一致性导致某些Miniapp
    在进行auth鉴权的时候用的launchParams和sign不一致导致鉴权不过从而导致一系列问题
    miniapp案例:https://vk.ru/vk_pro_sport_fantasy auth接口:https://prod.fantasy-league.vvdev.ru/api/v1/vk/auth
    */

    // event.data.vk_platform = 'mobile_android';
    // event.data.vk_language = 'en';
    return InterceptResult.hook(event);
  }

  @VkResponse('SetSupportedHandlers')
  setSupportedHandlers(event: VkBridgeEvent<VkSupportedHandlersData>): InterceptResult {
    const data = event.data;
    ParamAssert.assertObject(data, 'data');
    ParamAssert.assertStringArray(data.supportedHandlers, 'supportedHandlers');
    this.registry.updateRemoteSupportedHandlers(data.supportedHandlers);
    data.supportedHandlers = this.registry.getAvailableHandlers();

    SdkLogger.debug(TAG, 'supportedHandlersMerged', {
      sessionId: this.context.id, vendorId: VK_VENDOR_ID, count: data.supportedHandlers.length
    });
    return InterceptResult.hook(event);
  }

  @VkResponse('VKWebAppGetGroupInfoResult')
  getGroupInfo(event: VkBridgeEvent): InterceptResult {
    ParamAssert.assertObject(event.data, 'data');
    const data = event.data as VkWebGroupInfoData;
    // 单社区按 Android 实测包装；多社区保留官网 result 数组，不猜测客户端包装。
    if (data.group !== undefined || data.result !== undefined) {
      return InterceptResult.pass();
    }
    // 官网定义 0/1/2；枚举名称来自 VK 官方 Android SDK。未知状态保持原响应。
    ParamAssert.assertEnum(data.is_closed, 'is_closed', [0, 1, 2]);
    ParamAssert.assertNumber(data.id, 'id');
    ParamAssert.assertString(data.name, 'name');
    ParamAssert.assertString(data.screen_name, 'screen_name');
    // 官网允许私有社区省略描述与成员数；不为无法访问的数据补空串或零。
    if (data.is_closed === 2) {
      ParamAssert.assertOptionalString(data.description, 'description');
      ParamAssert.assertOptionalNumber(data.members_count, 'members_count');
    } else {
      ParamAssert.assertString(data.description, 'description');
      ParamAssert.assertNumber(data.members_count, 'members_count');
    }
    ParamAssert.assertString(data.type, 'type');
    ParamAssert.assertString(data.photo_50, 'photo_50');
    ParamAssert.assertString(data.photo_100, 'photo_100');
    ParamAssert.assertString(data.photo_200, 'photo_200');

    const group: VkAndroidGroupInfo = {
      description: data.description,
      id: data.id,
      is_closed: GROUP_CLOSED_STATES[data.is_closed],
      members_count: data.members_count,
      name: data.name,
      photo_100: data.photo_100,
      photo_200: data.photo_200,
      photo_50: data.photo_50,
      screen_name: data.screen_name,
      type: data.type
    };
    const result: VkGroupInfoResultData = { group };
    if (data.request_id !== undefined) {
      result.request_id = data.request_id;
    }
    // 校验和构造完成后再替换 data，保留原事件名及外层元数据。
    event.data = result;
    return InterceptResult.hook(event);
  }

  dispose(): void {
  }
}
