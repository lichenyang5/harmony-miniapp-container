import { formatLineLocale } from '../network/LineLocale';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { LineAccountManager } from './LineAccountManager';
import { LINE_COMPAT_ANDROID_RELEASE } from '../LineConstants';

/** HAR 所属应用的默认单账号槽位；不持有 UIAbility、WebView 或登录视图。 */
export class LineDefaultAccount {
  private static account?: LineAccountManager;

  static peek(): LineAccountManager | undefined {
    return LineDefaultAccount.account;
  }

  static get(context: common.UIAbilityContext): LineAccountManager {
    if (!LineDefaultAccount.account) {
      const model: string = deviceInfo.productModel;
      LineDefaultAccount.account = LineAccountManager.withConnInfo({
        androidRelease: LINE_COMPAT_ANDROID_RELEASE,
        locale: formatLineLocale(i18n.System.getSystemLocale(), i18n.System.getSystemRegion()),
        localeCountry: i18n.System.getSystemRegion()
      }, model, model, { persistent: true, storageContext: context.getApplicationContext() });
    }
    return LineDefaultAccount.account;
  }
}
