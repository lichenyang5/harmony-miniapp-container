import { BridgeContext } from '../../../core/Runtime';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';


export const VK_WEB_APP_GET_HEALTH_CONNECT: string = 'VKWebAppGetHealthConnectInfo';

export const VK_WEB_APP_GET_WORKOUTS_PERMISSIONS: string = 'VKWebAppGetWorkoutsPermissions';

enum HealthConnectInfo {
  /**
   * SDK 可用，不代表已授权读取数据
   */
  AVAILABLE = 'available',
  /**
   * 当前不可用
   */
  UNAVAILABLE = 'unavailable',
  /**
   * 需要安装；样本中对应 Android 14 以下未发现 Health Connect 应用
   */
  NEED_INSTALL = 'need_install',
  /**
   * 需要更新 Health Connect
   */
  NEED_UPDATE = 'need_update'
}

interface GetHealthConnectInfoResult {
  health_connect_info: HealthConnectInfo,
  sa_workout_health_connect: boolean,
  sa_steps_health_connect: boolean
}

enum WorkoutsPermissionState {
  /**
   * Google Fit
   * 活动识别可用、Google Play 服务可用 Google Fit 权限可用
   * Health Connect
   * SDK 可用、HC 权限已授予、活动识别可用
   */
  GRANTED = 'granted',
  /**
   * Google Fit
   * 未达到 granted，但 Google Play 服务可用
   * Health Connect
   * SDK 可用，但权限条件不完整
   */
  DISABLED_CAN_ASK = 'disabled_can_ask',
  /**
   * Google Fit
   * Google Play 服务不可用
   * Health Connect
   *  SDK 不可用、需安装或需更新
   */
  DISABLED = 'disabled'
}

interface GetWorkoutsPermissionsResult {
  permission_state: WorkoutsPermissionState,
  mobile_services_type: WorkoutsServicesType,

  /**
   * 活动识别是否可用
   */
  has_activity_recognition: boolean,

  /**
   *  VK 保存的运动同步开关, 仅 Google Fit
   */
  can_sync?: boolean
  /**
   * 实际表示 Google Fit 权限是否可用
   * 仅 Google Fit，且 Google Play 服务可用时
   */
  has_logged_gms?: boolean
}

enum WorkoutsServicesType {
  /**
   * Google 移动服务环境
   */
  GOOGLE_PLAY_SERVICES = 'google_play_services',
  /**
   * 华为移动服务环境
   */
  HUAWEI_MOBILE_SERVICES = 'huawei_mobile_services',
  /**
   * 未归入上述两种环境
   */
  NONE = 'none'
}

interface WorkoutsPermissionsParams {
  /**
   * 可选 boolean，默认 false    请求使用 Health Connect
   */
  use_health_connect?: boolean
}

export class VkHealthHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: VK_WEB_APP_GET_HEALTH_CONNECT })
  async getHealthConnect(params: object): Promise<GetHealthConnectInfoResult> {
    return {
      health_connect_info: HealthConnectInfo.UNAVAILABLE,
      sa_workout_health_connect: false,
      sa_steps_health_connect: false
    }
  }


  @VkEvent({ name: VK_WEB_APP_GET_WORKOUTS_PERMISSIONS })
  async getWorkoutsPermissions(params: WorkoutsPermissionsParams): Promise<GetWorkoutsPermissionsResult> {
    return {
      permission_state: WorkoutsPermissionState.DISABLED,
      mobile_services_type: WorkoutsServicesType.HUAWEI_MOBILE_SERVICES,
      has_activity_recognition: false
    }
  }

  dispose(): void {
  }
}
