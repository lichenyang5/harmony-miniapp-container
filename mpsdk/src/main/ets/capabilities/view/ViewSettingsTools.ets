import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/** VK 状态栏样式。 */
export type ViewStatusBarStyle = 'light' | 'dark';

/** 与 VK 协议字段解耦后的原生视图设置。 */
export interface ViewSettings {
  statusBarStyle: ViewStatusBarStyle;
  actionBarColor?: string;
  navigationBarColor?: string;
}

/** 供 VK Handler 调用的最小原生视图能力。 */
export interface ViewSettingsProvider {
  apply(settings: ViewSettings): Promise<void>;

  dispose(): void;
}

/** 隔离 HarmonyOS Window，便于验证协议到系统栏属性的映射。 */
export interface ViewSettingsWindow {
  getWindowSystemBarProperties(): window.SystemBarProperties;

  setWindowSystemBarProperties(properties: window.SystemBarProperties): Promise<void>;
}

export type ViewSettingsWindowProvider = () => Promise<ViewSettingsWindow>;

interface ViewSettingsWindowGroup {
  appWindow: ViewSettingsWindow;
  originalProperties: window.SystemBarProperties;
  controllers: ViewSettingsTools[];
  operation: Promise<void>;
  latestRevision: number;
}

type ViewSettingsOperation = () => Promise<void>;

/** HarmonyOS 系统栏设置工具。 */
export class ViewSettingsTools implements ViewSettingsProvider {
  private static readonly WINDOW_GROUPS: ViewSettingsWindowGroup[] = [];
  private static nextRevision: number = 0;
  private readonly windowProvider: ViewSettingsWindowProvider;
  private group?: ViewSettingsWindowGroup;
  private currentProperties?: window.SystemBarProperties;
  private disposed: boolean = false;

  constructor(context: common.UIAbilityContext, windowProvider?: ViewSettingsWindowProvider) {
    this.windowProvider = windowProvider ??
      (async (): Promise<ViewSettingsWindow> => await window.getLastWindow(context));
  }

  private static getOrCreateGroup(appWindow: ViewSettingsWindow): ViewSettingsWindowGroup {
    for (let index: number = 0; index < ViewSettingsTools.WINDOW_GROUPS.length; index++) {
      const group: ViewSettingsWindowGroup = ViewSettingsTools.WINDOW_GROUPS[index];
      if (group.appWindow === appWindow) {
        return group;
      }
    }
    const group: ViewSettingsWindowGroup = {
      appWindow,
      originalProperties: appWindow.getWindowSystemBarProperties(),
      controllers: [],
      operation: Promise.resolve(),
      latestRevision: 0
    };
    ViewSettingsTools.WINDOW_GROUPS.push(group);
    return group;
  }

  private static enqueue(group: ViewSettingsWindowGroup,
    operation: ViewSettingsOperation): Promise<void> {
    const running: Promise<void> = group.operation.then(operation, operation);
    group.operation = running.then((): void => {
    }, (): void => {
    });
    return running;
  }

  private static removeGroupIfUnused(group: ViewSettingsWindowGroup): void {
    if (group.controllers.length > 0) {
      return;
    }
    const groupIndex: number = ViewSettingsTools.WINDOW_GROUPS.indexOf(group);
    if (groupIndex >= 0) {
      ViewSettingsTools.WINDOW_GROUPS.splice(groupIndex, 1);
    }
  }

  async apply(settings: ViewSettings): Promise<void> {
    const revision: number = ++ViewSettingsTools.nextRevision;
    const appWindow: ViewSettingsWindow = await this.windowProvider();
    if (this.disposed) {
      return;
    }
    const group: ViewSettingsWindowGroup = ViewSettingsTools.getOrCreateGroup(appWindow);
    if (revision < group.latestRevision) {
      return;
    }
    group.latestRevision = revision;
    this.group = group;
    const baseProperties: window.SystemBarProperties =
      this.currentProperties ?? group.originalProperties;
    this.currentProperties = this.toSystemBarProperties(settings, baseProperties);
    const previousIndex: number = group.controllers.indexOf(this);
    if (previousIndex >= 0) {
      group.controllers.splice(previousIndex, 1);
    }
    group.controllers.push(this);
    const properties: window.SystemBarProperties = this.currentProperties;
    await ViewSettingsTools.enqueue(group, async (): Promise<void> => {
      const owner: ViewSettingsTools | undefined =
        group.controllers[group.controllers.length - 1];
      if (!this.disposed && this.group === group && owner === this) {
        await group.appWindow.setWindowSystemBarProperties(properties);
      }
    });
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    const group: ViewSettingsWindowGroup | undefined = this.group;
    this.group = undefined;
    this.currentProperties = undefined;
    if (!group) {
      return;
    }

    const controllerIndex: number = group.controllers.indexOf(this);
    if (controllerIndex < 0) {
      return;
    }
    const wasOwner: boolean = controllerIndex === group.controllers.length - 1;
    group.controllers.splice(controllerIndex, 1);
    if (!wasOwner) {
      return;
    }

    const restore: Promise<void> = ViewSettingsTools.enqueue(group, async (): Promise<void> => {
      const owner: ViewSettingsTools | undefined =
        group.controllers[group.controllers.length - 1];
      if (owner?.currentProperties) {
        await group.appWindow.setWindowSystemBarProperties(owner.currentProperties);
      } else if (group.controllers.length === 0) {
        await group.appWindow.setWindowSystemBarProperties(group.originalProperties);
      }
    });
    restore.then((): void => {
      ViewSettingsTools.removeGroupIfUnused(group);
    }, (): void => {
      ViewSettingsTools.removeGroupIfUnused(group);
    });
  }

  private toSystemBarProperties(settings: ViewSettings,
    baseProperties: window.SystemBarProperties): window.SystemBarProperties {
    const properties =
      JSON.parse(JSON.stringify(baseProperties)) as window.SystemBarProperties;
    properties.statusBarContentColor =
      settings.statusBarStyle === 'light' ? '#FFFFFF' : '#000000';
    properties.isStatusBarLightIcon = settings.statusBarStyle === 'light';
    if (settings.actionBarColor !== undefined) {
      properties.statusBarColor =
        settings.actionBarColor === 'none' ? '#00000000' : settings.actionBarColor;
    }
    if (settings.navigationBarColor !== undefined) {
      properties.navigationBarColor = settings.navigationBarColor;
    }
    return properties;
  }
}
