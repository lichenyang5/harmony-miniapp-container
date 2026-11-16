import { DocumentScript } from '../../../core/Runtime';
import { LineBridgeErrorCode } from '../LineErrorCode';
import { createLineSharePickerInstaller } from './LineSharePickerScript';

/** 将已注册的原生 Bridge 方法接入 LIFF API，并保留官方实现作为回退。 */
export function createLineLiffApiProxyScript(bridgeMethodNames: string[], webHookPicker: boolean = false): DocumentScript {
  return {
    required: true,
    scriptRules: ['*'],
    script: `(function () {
      ${webHookPicker ? createLineSharePickerInstaller() : ''}
      var methodNames = ${JSON.stringify(bridgeMethodNames)};
      var state = window.__atomicLineLiffApiProxy || {
        sequence: 0,
        pending: Object.create(null),
        liff: undefined
      };
      window.__atomicLineLiffApiProxy = state;

      function observeMethod(target, name, createProxy, onReplace) {
        var original = target[name];
        var proxy = createProxy(function () { return original; });
        try {
          Object.defineProperty(target, name, {
            configurable: true,
            enumerable: true,
            get: function () { return proxy; },
            set: function (method) {
              if (method !== proxy) {
                original = method;
                if (onReplace) onReplace();
              }
            }
          });
        } catch (_) {
          target[name] = proxy;
        }
        return target[name] === proxy;
      }

      function installDispatch(liff) {
        observeMethod(liff, '_dispatchEvent', function (getOriginal) {
          var proxy = function (eventJson) {
            var event;
            try {
              event = typeof eventJson === 'string' ? JSON.parse(eventJson) : eventJson;
            } catch (_) {
              var fallback = getOriginal();
              return fallback && fallback.apply(this, arguments);
            }
            var request = event && state.pending[event.callbackId];
            if (request) {
              delete state.pending[event.callbackId];
              console.debug('[LINE LIFF API proxy] response ' + event.type + ' success=' + !event.error);
              if (event.error) {
                var error = new Error(event.error.description || 'Unknown error');
                error.name = 'LiffError';
                error.code = event.error.code || '${LineBridgeErrorCode.UNKNOWN}';
                request.reject(error);
              } else {
                request.resolve(event.data);
              }
              return;
            }
            var fallback = getOriginal();
            return fallback && fallback.apply(this, arguments);
          };
          proxy.__atomicLineLiffApiProxyDispatch = true;
          return proxy;
        }, function () {
          console.debug('[LINE LIFF API proxy] dispatch-restored');
        });
      }

      function originalCall(getOriginal, liff, args) {
        var method = getOriginal();
        if (typeof method === 'function') return method.apply(liff, args);
        var error = new Error('The LIFF API is not available.');
        error.name = 'LiffError';
        error.code = '${LineBridgeErrorCode.FORBIDDEN}';
        return Promise.reject(error);
      }

      function serializeParams(args) {
        var params = args.length > 0 && args[0] !== undefined ? args[0] : {};
        return JSON.stringify(params);
      }

      function installApi(liff, apiName) {
        var installed = observeMethod(liff, apiName, function (getOriginal) {
          var proxy = function () {
            var args = Array.prototype.slice.call(arguments);
            var context;
            try {
              context = liff.getContext();
            } catch (_) {
              console.debug('[LINE LIFF API proxy] call ' + apiName + ' route=official reason=CONTEXT_ERROR');
              return originalCall(getOriginal, liff, args);
            }
            var bridge = window._liff;
            var reason = !context || !context.liffId ? 'CONTEXT_MISSING' :
              !bridge || typeof bridge.postMessage !== 'function' ? 'BRIDGE_METHOD_MISSING' :
              typeof liff._dispatchEvent !== 'function' ||
                !liff._dispatchEvent.__atomicLineLiffApiProxyDispatch ? 'DISPATCH_UNAVAILABLE' : '';
            if (reason) {
              console.debug('[LINE LIFF API proxy] call ' + apiName + ' route=official reason=' + reason);
              return originalCall(getOriginal, liff, args);
            }
            console.debug('[LINE LIFF API proxy] call ' + apiName + ' route=native');
            return new Promise(function (resolve, reject) {
              var callbackId = 'web-hook-' + apiName + '-' + Date.now() + '-' + (++state.sequence);
              state.pending[callbackId] = { resolve: resolve, reject: reject };
              try {
                bridge.postMessage(apiName, '', callbackId,
                  serializeParams(args));
              } catch (error) {
                delete state.pending[callbackId];
                reject(error);
              }
            });
          };
          proxy.__atomicLineLiffApiProxy = true;
          return proxy;
        }, function () {
          console.debug('[LINE LIFF API proxy] method-restored ' + apiName);
        });
        if (installed) console.debug('[LINE LIFF API proxy] method-installed ' + apiName);
      }

      function bind(liff) {
        var bridge = window._liff;
        if (!liff || !bridge || typeof bridge.postMessage !== 'function' || state.liff === liff) return;
        state.liff = liff;
        installDispatch(liff);
        for (var index = 0; index < methodNames.length; index += 1) {
          installApi(liff, methodNames[index]);
        }
        ${webHookPicker ? 'installSharePicker(liff, observeMethod);' : ''}
        console.debug('[LINE LIFF API proxy] bound methods=' + methodNames.join(','));
      }

      if (!window.__atomicLineLiffGlobalObserved) {
        try {
          var currentLiff = window.liff;
          Object.defineProperty(window, 'liff', {
            configurable: true,
            enumerable: true,
            get: function () { return currentLiff; },
            set: function (liff) {
              currentLiff = liff;
              bind(liff);
            }
          });
          window.__atomicLineLiffGlobalObserved = true;
        } catch (_) {
          // Some pages expose a non-configurable global; the current LIFF object is still bound below.
        }
      }
      bind(window.liff);
    })();`
  };
}
