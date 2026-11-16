import { AsyncCallback, BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { camera } from '@kit.CameraKit';
import { MiniAppError } from '../../core/MiniAppError';
import { NOT_SUPPORTED, SESSION_CLOSED, SYSTEM_ERROR } from '../../core/MiniAppErrorCode';
import {
  FlashPermissionGate,
  FlashPermissionProvider,
  HarmonyCameraPermissionGateway
} from './FlashPermissionGate';

/** 与 VK 协议无关的原生闪光灯状态。 */
export interface FlashInfo {
  isAvailable: boolean;
  level: number;
}

/** 供 VK 代理组合使用的最小查询能力。 */
export interface FlashInfoProvider {
  getInfo(): FlashInfo;

  setEnabled(enabled: boolean): Promise<void>;

  dispose(): void;
}

export type FlashOperationApplier = (enabled: boolean) => void;

/** 只允许最后一次开关请求在权限等待结束后操作硬件。 */
export class FlashOperationCoordinator {
  private readonly permissionGate: FlashPermissionProvider;
  private revision: number = 0;

  constructor(permissionGate: FlashPermissionProvider) {
    this.permissionGate = permissionGate;
  }

  async run(enabled: boolean, apply: FlashOperationApplier): Promise<void> {
    const revision: number = ++this.revision;
    await this.permissionGate.ensureAllowed(enabled);
    if (revision !== this.revision) {
      return;
    }
    apply(enabled);
  }
}

interface FlashSessionState {
  manager: camera.CameraManager;
  latestTorchStatus?: camera.TorchStatusInfo;
  torchStatusCallback: AsyncCallback<camera.TorchStatusInfo>;
}

/** HarmonyOS CameraKit 闪光灯工具；不解析 VK 方法名和 JSON。 */
export class FlashTools implements FlashInfoProvider {
  private static readonly CAMERA_ATOMIC_SERVICE_API: number = 19;
  private static readonly CONTROLLERS: FlashTools[] = [];
  private static restoreTorchMode?: camera.TorchMode;
  private readonly context: common.UIAbilityContext;
  private readonly operationCoordinator: FlashOperationCoordinator;
  private state?: FlashSessionState;
  private disposed: boolean = false;
  private requestedMode?: camera.TorchMode;

  constructor(context: common.UIAbilityContext, permissionGate?: FlashPermissionProvider) {
    this.context = context;
    const gate: FlashPermissionProvider = permissionGate ?? new FlashPermissionGate(
      new HarmonyCameraPermissionGateway(context));
    this.operationCoordinator = new FlashOperationCoordinator(gate);
  }

  /** 查询设备闪光灯是否可用以及当前二值亮度。 */
  getInfo(): FlashInfo {
    if (this.disposed || deviceInfo.sdkApiVersion < FlashTools.CAMERA_ATOMIC_SERVICE_API) {
      return { isAvailable: false, level: 0 };
    }
    const state: FlashSessionState | undefined = this.getOrCreateState();
    if (!state) {
      return { isAvailable: false, level: 0 };
    }
    const mode: camera.TorchMode = state.manager.getTorchMode();
    const isAvailable: boolean = state.latestTorchStatus?.isTorchAvailable ?? true;
    const isActive: boolean = mode === camera.TorchMode.ON ||
      (mode === camera.TorchMode.AUTO && state.latestTorchStatus?.isTorchActive === true);
    return { isAvailable, level: isActive ? 1 : 0 };
  }

  /** HarmonyOS 仅提供开关型手电筒：0 映射为关闭，正数映射为打开。 */
  async setEnabled(enabled: boolean): Promise<void> {
    if (this.disposed) {
      throw new MiniAppError(SESSION_CLOSED, '闪光灯控制器已释放');
    }
    if (deviceInfo.sdkApiVersion < FlashTools.CAMERA_ATOMIC_SERVICE_API) {
      throw new MiniAppError(NOT_SUPPORTED, '当前系统版本不支持原子化服务控制闪光灯');
    }
    await this.operationCoordinator.run(enabled, (latestEnabled: boolean): void => {
      this.applyEnabled(latestEnabled);
    });
  }

  /** 释放 CameraKit 状态监听。 */
  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    const state: FlashSessionState | undefined = this.state;
    this.state = undefined;
    if (!state) {
      return;
    }
    try {
      state.manager.off('torchStatusChange', state.torchStatusCallback);
    } catch (_) {
    }
    this.releaseControl(state.manager);
  }

  private applyEnabled(enabled: boolean): void {
    if (this.disposed) {
      throw new MiniAppError(SESSION_CLOSED, '闪光灯控制器已释放');
    }
    const state: FlashSessionState | undefined = this.getOrCreateState();
    if (!state) {
      throw new MiniAppError(NOT_SUPPORTED, '当前设备不支持闪光灯');
    }
    const targetMode: camera.TorchMode = enabled ? camera.TorchMode.ON : camera.TorchMode.OFF;
    if (!state.manager.isTorchModeSupported(targetMode)) {
      throw new MiniAppError(NOT_SUPPORTED, '当前设备不支持目标闪光灯模式');
    }
    const firstController: boolean = FlashTools.CONTROLLERS.length === 0;
    if (firstController) {
      FlashTools.restoreTorchMode = state.manager.getTorchMode();
    }
    try {
      state.manager.setTorchMode(targetMode);
    } catch (error) {
      if (firstController) {
        FlashTools.restoreTorchMode = undefined;
      }
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, '设置闪光灯失败');
    }
    const previousIndex: number = FlashTools.CONTROLLERS.indexOf(this);
    if (previousIndex >= 0) {
      FlashTools.CONTROLLERS.splice(previousIndex, 1);
    }
    this.requestedMode = targetMode;
    FlashTools.CONTROLLERS.push(this);
  }

  private getOrCreateState(): FlashSessionState | undefined {
    if (this.state) {
      return this.state;
    }
    let manager: camera.CameraManager;
    try {
      manager = camera.getCameraManager(this.context);
      if (!manager.isTorchSupported()) {
        return undefined;
      }
    } catch (_) {
      return undefined;
    }
    const callback: AsyncCallback<camera.TorchStatusInfo> =
      (error: BusinessError, status: camera.TorchStatusInfo): void => {
        if ((error === undefined || error.code === 0) && this.state) {
          this.state.latestTorchStatus = status;
        }
      };
    const state: FlashSessionState = {
      manager,
      torchStatusCallback: callback
    };
    this.state = state;
    try {
      manager.on('torchStatusChange', callback);
    } catch (_) {
      this.state = undefined;
      return undefined;
    }
    return state;
  }

  /** 当前控制者退出时恢复上一控制者的模式，最后一个退出时恢复进入前状态。 */
  private releaseControl(manager: camera.CameraManager): void {
    const controllerIndex: number = FlashTools.CONTROLLERS.indexOf(this);
    if (controllerIndex < 0) {
      return;
    }
    const wasOwner: boolean = controllerIndex === FlashTools.CONTROLLERS.length - 1;
    FlashTools.CONTROLLERS.splice(controllerIndex, 1);
    if (!wasOwner) {
      return;
    }

    let targetManager: camera.CameraManager = manager;
    let targetMode: camera.TorchMode | undefined;
    while (FlashTools.CONTROLLERS.length > 0) {
      const nextOwner: FlashTools = FlashTools.CONTROLLERS[FlashTools.CONTROLLERS.length - 1];
      if (nextOwner.state && nextOwner.requestedMode !== undefined) {
        targetManager = nextOwner.state.manager;
        targetMode = nextOwner.requestedMode;
        break;
      }
      FlashTools.CONTROLLERS.pop();
    }
    if (FlashTools.CONTROLLERS.length === 0) {
      targetMode = FlashTools.restoreTorchMode;
      FlashTools.restoreTorchMode = undefined;
    }
    if (targetMode === undefined) {
      return;
    }
    try {
      if (targetManager.isTorchModeSupported(targetMode)) {
        targetManager.setTorchMode(targetMode);
      }
    } catch (_) {
    }
  }
}
