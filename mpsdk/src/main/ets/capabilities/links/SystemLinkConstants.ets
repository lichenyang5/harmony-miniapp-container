/** 公共系统链接白名单；协议前缀从同一值派生。 */
export enum SystemLinkScheme {
  TEL = 'tel',
  MAILTO = 'mailto',
  SMS = 'sms'
}

/** 系统短信编辑页的固定入口，不接受网页指定目标应用。 */
export const SYSTEM_SMS_BUNDLE_NAME: string = 'com.ohos.mms';
export const SYSTEM_SMS_ABILITY_NAME: string = SYSTEM_SMS_BUNDLE_NAME + '.MainAbility';
export const SYSTEM_SMS_CONVERSATION_PAGE: string = 'conversation';
