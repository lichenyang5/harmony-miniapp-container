/** LINE 厂商标识；Adapter、Vendor 与窗口组装共用，避免为读取常量引入具体实现。 */
export const LINE_VENDOR_ID: string = 'line';

/** view.type 的原始协议值；当前主容器以 FULL 承载，允许 LIFF→LIFF 直接跳转。 */
export const LINE_LIFF_FULL_VIEW_TYPE: string = 'full';

/** 处理器注册、已知方法表和 Token 豁免共用同一个原生 Bridge 方法名。 */
export const LINE_CLOSE_WINDOW_METHOD: string = 'closeWindow';

export const LINE_SCAN_CODE_METHOD: string = 'scanCode';

export const LINE_SCAN_CODE_V2_METHOD: string = 'scanCodeV2';

export const LINE_OPEN_WINDOW_METHOD: string = 'openWindow';

/** 原生 picker 协议与当前文档分享适配之间的内部入口。 */
export const LINE_SHARE_PICKER_BRIDGE_NAME: string = '__atomicLineSharePicker';

/** 当前已验证的 Android 兼容配置；不是 HarmonyOS 系统版本或账号设备标识。 */
export const LINE_COMPAT_ANDROID_RELEASE: string = '14';

/** WEB 模式已验证兼容 UA：保留 OpenHarmony/ArkWeb 特征，仅增加 Android 平台兼容标识。 */
export const LINE_WEB_USER_AGENT: string =
  `Mozilla/5.0 (Phone; OpenHarmony 5.0; Android ${LINE_COMPAT_ANDROID_RELEASE}) AppleWebKit/537.36 ` +
  '(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile';

export const LINE_CLIENT_USER_AGENT: string =
  `Mozilla/5.0 (Linux; Android ${LINE_COMPAT_ANDROID_RELEASE}) AppleWebKit/537.36 ` +
  '(KHTML, like Gecko) Version/4.0 Chrome/130.0.6723.86 Mobile Safari/537.36 Line/26.15.1 LIFF';
