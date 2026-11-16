import { LineMode } from './LineMode';
import { LineAppState } from './LineAppState';
import { LineBridgeError } from './LineBridgeError';
import { LineBridgeRequest } from './LineBridgeProtocol';
import {
  LINE_CLOSE_WINDOW_METHOD, LINE_OPEN_WINDOW_METHOD, LINE_SCAN_CODE_METHOD
} from './LineConstants';

/** 固定 APK 普通 LIFF provider 的方法目录，不代表本 SDK 已实现这些能力。 */
const KNOWN_METHODS: string[] = [
  LINE_OPEN_WINDOW_METHOD,
  LINE_CLOSE_WINDOW_METHOD,
  LINE_SCAN_CODE_METHOD,
  'addToHomeScreen',
  'getAdvertisingId',
  'calendar.getEvents',
  'calendar.showEventCreationModal',
  'iap.createPayment',
  'iap.getPlatformProducts',
  'iap.requestConsentAgreement'
];

/** 方法目录与 Token 规则；调用前必须确认会话、文档、来源和桥状态。 */
export class LineFeaturePolicy {
  static isKnownMethod(type: string): boolean {
    return KNOWN_METHODS.indexOf(type) >= 0;
  }

  static checkToken(request: LineBridgeRequest, state?: LineAppState): LineBridgeError | undefined {
    const bypass = state?.lineMode === LineMode.WEB_HOOK || request.type === LINE_CLOSE_WINDOW_METHOD
    if (bypass) {
      return undefined
    }
    const expectedFeatureToken = state?.featureToken
    if (expectedFeatureToken !== undefined && request.featureToken !== expectedFeatureToken) {
      return LineBridgeError.noAuthority();
    }
    return undefined;
  }
}
