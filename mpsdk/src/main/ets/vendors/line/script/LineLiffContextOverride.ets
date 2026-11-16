import { DocumentScript } from '../../../core/Runtime';

/** WEB/WEB_HOOK：页面读取前把 external 的 LIFF 上下文归一化，避免页面仅按浏览器类型直接拦截。 */
export function createLineLiffContextOverrideScript(type: string): DocumentScript {
  return {
    required: true,
    scriptRules: ['*'],
    script: `(function () {
      var logTag = '[LINE ContextType]';
      var contextKey = /^LIFF_STORE:[^:]+:context$/;
      var overrideType = '${type}';
      if (window.__atomicLineContextTypeOverride) {
        console.debug(logTag, 'recheck');
        return;
      }
      window.__atomicLineContextTypeOverride = { type: overrideType };
      function normalize(value) {
        try {
          var context = JSON.parse(value);
          if (!context || context.type !== 'external') {
            return value;
          }
          context.type = overrideType;
          return JSON.stringify(context);
        } catch (_) {
          return value;
        }
      }
      function normalizeStorage(storage) {
        if (!storage) {
          return;
        }
        try {
          for (var index = 0; index < storage.length; index += 1) {
            var key = storage.key(index);
            if (!contextKey.test(key)) {
              continue;
            }
            var value = storage.getItem(key);
            var next = normalize(value);
            if (next !== value) {
              storage.setItem(key, next);
            }
          }
        } catch (_) {
          console.warn(logTag, 'storage-scan-failed');
        }
      }
      normalizeStorage(window.localStorage);
      normalizeStorage(window.sessionStorage);
      var prototype = window.Storage && window.Storage.prototype;
      if (!prototype || typeof prototype.setItem !== 'function') {
        console.warn(logTag, 'storage-unavailable');
        return;
      }
      var setItem = prototype.setItem;
      prototype.setItem = function (key, value) {
        return setItem.call(this, key, contextKey.test(key) ? normalize(value) : value);
      };
      console.debug(logTag, 'installed', overrideType);
    })();`
  };
}
