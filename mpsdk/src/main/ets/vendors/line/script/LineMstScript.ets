import { DocumentScript } from '../../../core/Runtime';
import { LineErrorCode } from '../LineErrorCode';

/** 兼容 LIFF 2.31.1 in-client 存储格式；必须在网页初始化之前执行。 */
export function createLineMstScript(appId: string, challenge: string): DocumentScript {
  const key: string = JSON.stringify(`LIFF_STORE:${appId}:mstChallenge`);
  const value: string = JSON.stringify(JSON.stringify(challenge));
  return {
    required: true,
    scriptRules: ['*'],
    script: `(function () {
      if (window.top !== window) return;
      if (window.location.protocol !== 'https:' && window.location.protocol !== 'http:') return;
      try {
        sessionStorage.setItem(${key}, ${value});
      } catch (_) {
        console.warn('[MPSDK] ${LineErrorCode.MST_STORAGE_UNAVAILABLE}');
      }
    })();`
  };
}
