import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import {
  ViewSettings,
  ViewSettingsProvider,
  ViewSettingsTools,
  ViewStatusBarStyle
} from '../../../capabilities/view/ViewSettingsTools';
import { BridgeContext } from '../../../core/Runtime';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';

export const VK_WEB_APP_SET_VIEW_SETTINGS: string = 'VKWebAppSetViewSettings';

export type ViewSettingsProviderFactory = () => ViewSettingsProvider;

export interface VkViewSettingsParams {
  status_bar_style: string;
  action_bar_color?: string;
  navigation_bar_color?: string;
}

interface VkBooleanResult {
  result: boolean;
}

/** VK 视图设置协议适配器。 */
export class VkViewSettingsHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly providerFactory: ViewSettingsProviderFactory;
  private provider?: ViewSettingsProvider;

  constructor(context: BridgeContext, providerFactory?: ViewSettingsProviderFactory) {
    this.context = context;
    this.providerFactory = providerFactory ??
      ((): ViewSettingsProvider => new ViewSettingsTools(context.uiAbilityContext));
  }

  @VkEvent({ name: VK_WEB_APP_SET_VIEW_SETTINGS })
  async setViewSettings(params: VkViewSettingsParams): Promise<VkBooleanResult> {
    ParamAssert.assertObject(params, 'params');
    ParamAssert.assertEnum(params.status_bar_style, 'status_bar_style', ['light', 'dark']);
    ParamAssert.assertOptionalString(params.action_bar_color, 'action_bar_color', false);
    ParamAssert.assertOptionalString(params.navigation_bar_color, 'navigation_bar_color', false);
    try {
      const settings: ViewSettings = {
        statusBarStyle: params.status_bar_style as ViewStatusBarStyle,
        actionBarColor: params.action_bar_color,
        navigationBarColor: params.navigation_bar_color
      };
      await this.getProvider().apply(settings);
      const result: VkBooleanResult = { result: true };
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  dispose(): void {
    this.provider?.dispose();
    this.provider = undefined;
  }

  private getProvider(): ViewSettingsProvider {
    if (this.provider) {
      return this.provider;
    }
    const provider: ViewSettingsProvider = this.providerFactory();
    this.provider = provider;
    this.context.addCleanup((): void => {
      if (this.provider === provider) {
        provider.dispose();
        this.provider = undefined;
      }
    });
    return provider;
  }
}
