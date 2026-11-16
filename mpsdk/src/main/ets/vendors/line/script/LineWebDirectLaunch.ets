import { DocumentScript } from '../../../core/Runtime';
import { LINE_LIFF_HOST, LINE_MINIAPP_HOST } from '../scheme/LineSchemeConstants';

/** WEB 模式跳过 LINE 的“用浏览器打开”引导页，直接加载其声明的 Mini App 地址。 */
export function createLineWebDirectLaunchScript(): DocumentScript {
  return {
    required: true,
    scriptRules: ['*'],
    script: `(function () {
      var logTag = '[LINE WebDirectLaunch]';
      console.info(logTag, 'entered');
      if (window.top !== window) {
        console.info(logTag, 'skip-frame');
        return;
      }
      var hostname = location.hostname.toLowerCase();
      if (hostname !== '${LINE_MINIAPP_HOST}' && hostname !== '${LINE_LIFF_HOST}') {
        console.info(logTag, 'skip-host');
        return;
      }
      if (typeof window.__atomicLineWebDirectLaunch === 'function') {
        console.info(logTag, 'recheck');
        window.__atomicLineWebDirectLaunch();
        return;
      }
      var observer;
      var redirected = false;
      function submitTarget(rawTarget, source) {
        if (redirected) {
          return true;
        }
        if (typeof rawTarget !== 'string' || rawTarget.length === 0) {
          return false;
        }
        var target;
        try {
          target = new URL(rawTarget, location.href);
        } catch (_) {
          return false;
        }
        if (target.protocol !== 'https:') {
          console.warn(logTag, 'invalid-target');
          return false;
        }
        redirected = true;
        if (observer) {
          observer.disconnect();
        }
        console.info(logTag, 'redirect-submitted', source);
        location.replace(target.href);
        return true;
      }
      function redirectFromLiffInfo() {
        var info = window.liffInfo;
        return !!info && submitTarget(info.liffAppUrlForBrowser, 'liff-info');
      }
      function redirectFromLink() {
        var link = document.getElementById('linkOpenInBrowserLink');
        return !!link && link.tagName === 'A' &&
          submitTarget(link.getAttribute('href') || '', 'browser-link');
      }
      function checkTarget() {
        return redirectFromLiffInfo() || redirectFromLink();
      }
      window.__atomicLineWebDirectLaunch = checkTarget;
      if (checkTarget()) {
        return;
      }
      try {
        Object.defineProperty(window, 'liffInfo', {
          configurable: true,
          enumerable: true,
          get: function () {
            return undefined;
          },
          set: function (value) {
            Object.defineProperty(window, 'liffInfo', {
              configurable: true,
              enumerable: true,
              writable: true,
              value: value
            });
            if (value) {
              submitTarget(value.liffAppUrlForBrowser, 'liff-info');
            }
          }
        });
        console.info(logTag, 'liff-info-hook-installed');
      } catch (_) {
        console.warn(logTag, 'liff-info-hook-failed');
      }
      observer = new MutationObserver(function () {
        redirectFromLink();
      });
      observer.observe(document, { childList: true, subtree: true });
      console.info(logTag, 'observer-installed');
      document.addEventListener('DOMContentLoaded', checkTarget, { once: true });
      setTimeout(function () {
        observer.disconnect();
      }, 10000);
    })();`
  };
}
