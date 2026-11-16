/** WebSchemeHandler 使用不含冒号的 scheme；URL.protocol 比较时在此基础上附加冒号。 */
export const LINE_LIFF_SCHEME: string = 'liff';
export const LINE_HTTP_SCHEME: string = 'http';
export const LINE_HTTPS_SCHEME: string = 'https';

/** 普通网页中请求打开 LINE 小程序的深链；不用于建立 featureToken。 */
export const LINE_APP_SCHEME: string = 'line';
/** LINE 全局功能地址；这里只接入二维码读取器，不实现全部 /R/ 或 nv 命令。 */
export const LINE_FEATURE_HOST: string = 'line.me';
export const LINE_QR_READER_PATH: string = '/QRCodeReader';
export const LINE_NATIVE_VIEW_HOST: string = 'nv';
export const LINE_QR_READER_HTTP_PATH: string = '/R/' + LINE_NATIVE_VIEW_HOST + LINE_QR_READER_PATH;
export const LINE_LIFF_HOST: string = 'liff.line.me';
export const LINE_MINIAPP_HOST: string = 'miniapp.line.me';
export const LINE_ACCESS_HOST: string = 'access.line.me';
export const LINE_SHARE_PICKER_HOST: string = 'picker';
export const LINE_SHARE_PICKER_URL: string = 'https://' + LINE_ACCESS_HOST + '/oauth2/v2.1/liff/shareTargetPicker';
export const LINE_OAUTH_LOGIN_PATHS: string[] = ['/oauth2/v2.1/login', '/dialog/oauth/weblogin'];
export const LINE_LIFF_APP_URL_PREFIX: string = 'https://' + LINE_LIFF_HOST + '/';

export const LINE_CONSENT_SCHEME: string = 'lineconnect';

/** LIFF 地址中的命令名，保持大小写精确匹配。 */
export enum LineLiffCommand {
  APP = 'app',
  SUBWINDOW = 'subwindow',
  CLOSE = 'close'
}

/** 官方授权回调的命令名；retry 与 allow 均表示重新发行视图。 */
export enum LineConsentCommand {
  ALLOW = 'allow',
  RETRY = 'retry',
  DISALLOW = 'disallow'
}
