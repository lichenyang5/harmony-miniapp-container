import { DocumentScript } from '../../../core/Runtime';

/**
 * WEB/WEB_HOOK：LIFF 初始化完成后补一次官方网页登录。
 * 页面只读 access token、自身不调用 login 时由这里补齐，登录成功返回后正常加载。
 */
export function createLineLiffLoginScript(): DocumentScript {
  return {
    required: true,
    scriptRules: ['*'],
    script: `(function () {
      var logTag = '[LINE WebLogin]';
      if (window.top !== window) {
        return;
      }
      if (window.location.protocol !== 'https:' || window.location.hostname === 'access.line.me') {
        return;
      }
      if (/[?&](code|error)=/.test(window.location.search)) {
        console.debug(logTag, 'skip-callback');
        return;
      }
      var attemptKey = '__atomicLineWebLoginAttempts';
      function readAttempts() {
        try {
          return Number(window.sessionStorage.getItem(attemptKey) || '0');
        } catch (_) {
          return 0;
        }
      }
      function clearAttempts() {
        try {
          window.sessionStorage.removeItem(attemptKey);
        } catch (_) {
        }
      }
      var timer = window.setInterval(function () {
        var liff = window.liff;
        if (!liff || typeof liff.getContext !== 'function') {
          return;
        }
        try {
          liff.getContext();
        } catch (_) {
          return;
        }
        window.clearInterval(timer);
        try {
          if (typeof liff.isInClient === 'function' && liff.isInClient()) {
            console.debug(logTag, 'skip-client');
            return;
          }
          if (typeof liff.isLoggedIn === 'function' && liff.isLoggedIn()) {
            clearAttempts();
            console.debug(logTag, 'already-logged-in');
            return;
          }
          var attempts = readAttempts();
          if (attempts >= 2) {
            console.debug(logTag, 'skip-limit');
            return;
          }
          attempts += 1;
          window.sessionStorage.setItem(attemptKey, String(attempts));
          console.debug(logTag, 'login', attempts);
          var result = liff.login();
          if (result && typeof result.catch === 'function') {
            result.catch(function () {
              console.warn(logTag, 'login-failed');
            });
          }
        } catch (_) {
          console.warn(logTag, 'failed');
        }
      }, 200);
      window.setTimeout(function () {
        window.clearInterval(timer);
      }, 30000);
    })();`
  };
}
