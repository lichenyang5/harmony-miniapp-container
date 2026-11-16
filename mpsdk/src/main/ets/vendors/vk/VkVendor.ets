import {
  BridgeContext,
  BridgeInjection,
  DocumentScript,
  MiniAppSession,
  Vendor,
  VendorBinding
} from '../../core/Runtime';
import { SdkLogger } from '../../logging/SdkLogger';
import { VkAudioHandler } from './handlers/VkAudioHandler';
// 暂停原生接管，复用 VK Web 的授权和用户资料能力；保留实现以便恢复。
// import { VkAuthTokenHandler } from './handlers/VkAuthTokenHandler';
import { VkClientMessageHandler } from './handlers/VkClientMessageHandler';
import { VkCloseHandler } from './handlers/VkCloseHandler';
import { VkBridgeProxy } from './VkBridgeProxy';
import { VkFlashHandler } from './handlers/VkFlashHandler';
import { VK_WEB_APP_OPEN_CODE_READER, VkMediaHandler } from './handlers/VkMediaHandler';
import { VkHapticHandler } from './handlers/VkHapticHandler';
import { VkPermissionHandler } from './handlers/VkPermissionHandler';
import { VkSwipeSettingsHandler } from './handlers/VkSwipeSettingsHandler';
import { VkViewSettingsHandler } from './handlers/VkViewSettingsHandler';
import { VkEventRegistry } from './events/VkEventRegistry';
import { MiniAppError } from '../../core/MiniAppError';
import { INVALID_ARGUMENT, VENDOR_BINDING_FAILED } from '../../core/MiniAppErrorCode';
import { BaseVkEventHandler } from './events/BaseVkEventHandler';
import { VkResponseInterceptor } from './interceptors/VkResponseInterceptor';
import { VendorAdapter } from '../../core/VendorAdapter';
import { VkAdapter } from './VkAdapter';
import BuildProfile from '../../../../../BuildProfile';
import { VkUsersHandler } from './handlers/VkUsersHandler';
import { VkPersonalCardHandler } from './handlers/VkPersonalCardHandler';
import { VkTestBannerHandler } from './handlers/VkTestBannerHandler';
import { VkTestBannerController } from './testing/VkTestBannerController';
import { VkTestNativeAdController } from './testing/VkTestNativeAdController';
import { VkTestNativeAdsHandler } from './handlers/VkTestNativeAdsHandler';
import { VkMiniAppIdentity } from './VkMiniAppIdentity';
import { VkLaunchParams } from './VkLaunchParams';
import { VkHealthHandler } from './handlers/VkHealthHandler';
import { VkClientHandler } from './handlers/VkClientHandler';
import { VkAccelerometerHandler } from './handlers/VkAccelerometerHandler';
import { VkGyroscopeHandler } from './handlers/VkGyroscopeHandler';
import { VkDeviceMotionHandler } from './handlers/VkDeviceMotionHandler';

export const VK_VENDOR_ID: string = 'vk';

const TAG: string = 'VkBridge';
const VK_NATIVE_PROXY_NAME: string = 'HosBridge';

/** 放在现有登录脚本前；由已有 HostPatch 定时器复查，不增加路由 hook。 */
function createVkMiniAppIdentityScript(initialUrl: string): string {
  return `
(function () {
    if (window !== window.top || window.__vkMiniAppIdentity) return;
    function route(address) {
        try {
            var parsed = new URL(address);
            if (parsed.protocol !== 'https:' || !/^(m\\.)?vk\\.(ru|com)$/i.test(parsed.hostname) ||
                parsed.username || parsed.password || parsed.port) return '';
            var game = /^\\/games\\/(app[0-9]+)(?:\\/.*)?$/i.exec(parsed.pathname);
            if (game) return '/' + game[1];
            var pathMatch = /^(\\/[A-Za-z0-9_.-]+)(?:\\/.*)?$/.exec(parsed.pathname.replace(/\\/+$/, ''));
            var path = pathMatch ? pathMatch[1] : '';
            if (!path ||
                /^\\/(feed|login|join|auth|settings|im|friends|news|support|games)$/i.test(path)) return '';
            return path;
        } catch (_) { return ''; }
    }
    if (location.protocol !== 'https:' || !/^(m\\.)?vk\\.(ru|com)$/i.test(location.hostname)) return;
    var entry = route(${JSON.stringify(initialUrl)}), reported = '';
    function scan() {
        var current = route(location.href), found = [], frames = document.querySelectorAll('iframe');
        for (var i = 0; i < frames.length; i++) {
            try {
                var url = new URL(frames[i].getAttribute('src') || frames[i].src, location.href);
                var params = url.searchParams, id = params.get('vk_app_id');
                if (url.protocol === 'https:' && /^[0-9]+$/.test(id || '') &&
                    params.get('vk_user_id') && params.get('sign')) found.push(id);
            } catch (_) {}
        }
        var id = found.length === 1 ? found[0] : '';
        var canonical = /^\\/app([0-9]+)$/i.exec(current);
        var entryId = /^\\/app([0-9]+)$/i.exec(entry);
        var valid = !!(entry && current && id && (!entryId || entryId[1] === id) &&
            (current === entry || (canonical && canonical[1] === id)));
        if (valid && reported !== current + ':' + id && window.HosBridge &&
            typeof window.HosBridge.onMiniAppIdentified === 'function') {
            try {
                if (!window.HosBridge.onMiniAppIdentified(location.href, id)) return false;
                reported = current + ':' + id;
            } catch (_) {}
        }
        return valid;
    }
    window.__vkMiniAppIdentity = {
        scan: scan,
        hasMiniApp: scan,
        isTargetApp: function () {
            var observed = scan();
            return !!(entry && route(location.href) === entry) || observed;
        }
    };
    scan();
})();
`;
}

const loginScript: string = `
// loginScript
(function () {
    'use strict';

    // 只在顶层文档运行，iframe 内不执行
    if (window !== window.top) return;

    const LOGIN_URL = 'https://m.vk.ru/';
    const SUCCESS_URL = 'https://m.vk.ru/feed';
    const STORAGE_KEY = 'vk_app_pending';
    const LOGGED_FLAG = 'vk_app_logged_in';

    const href = location.href;
    const isVkHost = location.protocol === 'https:' && ['vk.ru', 'm.vk.ru', 'vk.com', 'm.vk.com'].indexOf(location.hostname.toLowerCase()) >= 0;
    // Configured entry or observed launch iframe; aliases do not need an /app prefix.
    const isTargetApp = !!window.__vkMiniAppIdentity && window.__vkMiniAppIdentity.isTargetApp();

    console.log('%c[VK Login v1] 已加载', 'color: green; font-weight: bold', JSON.stringify({
        href: href,
        isVkHost: isVkHost,
        isTargetApp: isTargetApp
    }));

    if (!isVkHost) return;

    // ----- 目标 App 页面：未登录则跳登录 -----
    // 原有辅助登录只处理 m.vk.ru，桌面/其他域名继续由 VK 自身跳转，避免跨域丢失 pending。
    if (isTargetApp && location.hostname.toLowerCase() === 'm.vk.ru') {
        var alreadyLogged =
            sessionStorage.getItem(LOGGED_FLAG) ||
            localStorage.getItem(LOGGED_FLAG);

        if (alreadyLogged || window.__vkMiniAppIdentity.hasMiniApp()) {
            console.log('%c已登录过，直接进入 App，不再跳转', 'color: green');
            return;
        }

        console.log('%c检测到目标App且未登录，跳转到登录页...', 'color: orange');
        sessionStorage.setItem(STORAGE_KEY, location.href);
        localStorage.setItem(STORAGE_KEY, location.href);
        location.replace(LOGIN_URL);
        return;
    }

    // ----- 登录成功检测 -----
    function checkSuccess() {
        var current = location.href;
        if (!(current.indexOf(SUCCESS_URL) === 0 || current.indexOf('/feed') !== -1)) {
            return;
        }

        var target =
            sessionStorage.getItem(STORAGE_KEY) ||
            localStorage.getItem(STORAGE_KEY);
        if (!target) return;

        console.log(
            '%c检测到登录成功 (/feed)，准备跳回 App',
            'color: green; font-weight: bold'
        );

        sessionStorage.setItem(LOGGED_FLAG, '1');
        localStorage.setItem(LOGGED_FLAG, '1');
        sessionStorage.removeItem(STORAGE_KEY);
        localStorage.removeItem(STORAGE_KEY);

        setTimeout(function () {
            console.log('正在跳回目标App:', target);
            location.replace(target);
        }, 1);
    }

    checkSuccess();
    setInterval(checkSuccess, 500);
    window.addEventListener('popstate', checkSuccess);
    window.addEventListener('hashchange', checkSuccess);
})();

`;
const vkHostPatchScript: string = `
// VK host page patches. This script must never run inside the miniapp iframe.
(function () {
    'use strict';
    console.log('[VK HostPatch] script entered');
    const href = location.href;
    const isTopWindow = window === window.top;
    // Keep these checks aligned with loginScript.
    const isVkHost = location.protocol === 'https:' && ['vk.ru', 'm.vk.ru', 'vk.com', 'm.vk.com'].indexOf(location.hostname.toLowerCase()) >= 0;
    // Configured entry or observed launch iframe; aliases do not need an /app prefix.
    const isTargetApp = !!window.__vkMiniAppIdentity && window.__vkMiniAppIdentity.isTargetApp();
    console.log('[VK HostPatch] documentStart', JSON.stringify({
        href: href,
        hostname: location.hostname,
        isTopWindow: isTopWindow,
        isVkHost: isVkHost,
        isTargetApp: isTargetApp,
        hasApps: !!window.Apps
    }));

    if (!isTopWindow) {
        console.log('[VK HostPatch] skip: miniapp iframe');
        return;
    }
    if (!isVkHost) {
        console.log('[VK HostPatch] skip: non-VK host', href);
        return;
    }
    if (!isTargetApp) {
        console.log('[VK HostPatch] waiting for target miniapp iframe');
    }
    if (window.__vkHostPatchInstalled) {
        console.log('[VK HostPatch] skip: already installed');
        return;
    }
    window.__vkHostPatchInstalled = true;
    console.log('[VK HostPatch] installing', href);

    function isHeaderCloseClick(event) {
        if (!event || event.type !== 'click') return false;
        var element = event.currentTarget;
        if (!element || typeof element.closest !== 'function') element = event.target;
        if (!element || typeof element.closest !== 'function') return false;
        var button = element.closest('a.vkAppHeader__back');
        if (!button || !button.closest('div[class*="vkAppHeader"]')) return false;
        // 取消图标不依赖页面语言；不能把所有顶部返回按钮都当作关闭。
        return !!button.querySelector('.svgIcon-cancel_16') || button.getAttribute('aria-label') === '关闭';
    }

    function requestHostGoBack() {
        try {
            if (!window.HosBridge || typeof window.HosBridge.onHostGoBack !== 'function') {
                console.error('[VK HostPatch] HosBridge.onHostGoBack unavailable');
                return;
            }
            window.HosBridge.onHostGoBack();
        } catch (error) {
            console.error('[VK HostPatch] native back handling failed', error);
        }
    }

    var goBackHook = function (event) {
        console.log('[VK HostPatch] Apps.goBack called');
        try {
            // onclick 没有 return，必须显式取消链接的默认 /apps 跳转。
            if (event && typeof event.preventDefault === 'function') event.preventDefault();
            if (isHeaderCloseClick(event)) {
                console.log('[VK HostPatch] header close requested');
                if (!window.HosBridge || typeof window.HosBridge.onHostClose !== 'function') {
                    console.error('[VK HostPatch] HosBridge.onHostClose unavailable');
                    return;
                }
                window.HosBridge.onHostClose();
                return;
            }
            requestHostGoBack();
        } catch (error) {
            console.error('[VK HostPatch] Apps.goBack handling failed', error);
        }
    };
    var missingAppsLogged = false;
    var navBackHook;

    function isTargetMiniApp() {
        return !!window.__vkMiniAppIdentity && window.__vkMiniAppIdentity.isTargetApp();
    }

    function hookNavBack() {
        if (!isTargetMiniApp() || !window.nav ||
            typeof window.nav.backToTabHistory !== 'function') return;
        if (window.nav.backToTabHistory === navBackHook) return;
        var original = window.nav.backToTabHistory;
        var replacement = function () {
            // nav 属于全站共享对象，同文档切到登录等非目标页面后保留原行为。
            if (!isTargetMiniApp()) return original.apply(this, arguments);
            console.log('[VK HostPatch] nav.backToTabHistory called');
            requestHostGoBack();
            // 支持 onclick="return nav.backToTabHistory(this)"，不执行原始 href 回退。
            return false;
        };
        try {
            window.nav.backToTabHistory = replacement;
            if (window.nav.backToTabHistory === replacement) {
                navBackHook = replacement;
                console.log('[VK HostPatch] nav.backToTabHistory hooked');
            }
        } catch (error) {
            console.error('[VK HostPatch] nav.backToTabHistory hook failed', error);
        }
    }

    // backToTabHistory 的首参是链接元素，不是 Event；没有 return 的内联处理器还需取消默认跳转。
    // 此处只取消默认动作，实际返回仍由处理器调用 Hook，避免一次点击提交两次返回。
    window.addEventListener('click', function (event) {
        if (!isTargetMiniApp()) return;
        var target = event.target;
        if (target && typeof target.closest !== 'function') target = target.parentElement;
        var link = target && typeof target.closest === 'function' ? target.closest('a[onclick]') : null;
        if (!link || !/\\bnav\\.backToTabHistory\\s*\\(/.test(link.getAttribute('onclick') || '')) return;
        hookNavBack();
        event.preventDefault();
    }, true);

    function hookGoBack() {
        if (!window.__vkMiniAppIdentity || !window.__vkMiniAppIdentity.isTargetApp()) return false;
        if (!window.Apps || (typeof window.Apps !== 'object' && typeof window.Apps !== 'function')) {
            if (!missingAppsLogged) {
                console.log('[VK HostPatch] Apps is not ready');
                missingAppsLogged = true;
            }
            return false;
        }
        missingAppsLogged = false;
        if (window.Apps.goBack === goBackHook) {
            return true;
        }
        try {
            window.Apps.goBack = goBackHook;
            console.log('[VK HostPatch] Apps.goBack hooked');
        } catch (error) {
            console.error('[VK HostPatch] Apps.goBack hook failed', error);
            return false;
        }
        return true;
    }

    // Apps may be created after the document-start injection.
    var hookTimer = setInterval(function () {
        hookGoBack();
        hookNavBack();
    }, 200);
    hookGoBack();
    hookNavBack();
    window.addEventListener('pagehide', function () {
        clearInterval(hookTimer);
    });
})();
`;
const vkAndroidBridgeScript: string = `
(function () {
    'use strict';
    if (window === window.top) return;

    var href = location.href;
    var params;
    try {
        params = new URL(href).searchParams;
    } catch (error) {
        console.error('[VK AndroidBridge] invalid iframe URL:', error);
        return;
    }
    if (!params.has('vk_app_id') || !params.has('vk_user_id') || !params.has('sign')) return;

    if (window.AndroidBridge) {
        console.log('[VK AndroidBridge] existing bridge preserved', href);
        return;
    }

    function forwardToVkHost(method, serializedData) {
        var props = {};
        try {
            if (serializedData !== undefined && serializedData !== null && serializedData !== '') {
                props = typeof serializedData === 'string' ? JSON.parse(serializedData) : serializedData;
            }
            if (props === null || typeof props !== 'object' || Array.isArray(props)) {
                props = { raw: props };
            }
        } catch (error) {
            console.warn('[VK AndroidBridge] params parse failed:', method, error);
            props = { raw: serializedData };
        }

        var payload = {
            handler: method,
            params: props,
            type: 'vk-connect',
            connectVersion: '3.0.2'
        };
        console.log('[VK AndroidBridge] forward:', method, JSON.stringify(payload));
        try {
            window.parent.postMessage(payload, '*');
        } catch (error) {
            console.error('[VK AndroidBridge] parent.postMessage failed:', method, error);
        }
    }
    var methodCache = Object.create(null);
    var supportedHandlers;
    function supportsMethod(method) {
        if (typeof method !== 'string' || method === 'then') return false;
        if (supportedHandlers && supportedHandlers.includes(method)) return true;
        try {
            supportedHandlers = window.HosBridge.supportedHandlers() ?? [];
        } catch (_) {
            return false;
        }
        let supported = supportedHandlers.includes(method);
        if (!supported) {
            console.warn(method + ' unsupported!');
        }
        return supported;
    }
    window.AndroidBridge = new Proxy({}, {
        get: function (_target, method) {
            // if (typeof method === 'symbol' || method === 'then') return undefined;
            var methodName = String(method);
            if (!supportsMethod(methodName)) {
              // return undefined;
            }
            if (!methodCache[methodName]) {
                methodCache[methodName] = function (serializedData) {
                    forwardToVkHost(methodName, serializedData);
                };
            }
            return methodCache[methodName];
        },
        has: function (_target, method) {
            return supportsMethod(method);
        }
    });
    console.log('[VK AndroidBridge] installed', href);
})();
`;
const hookScript: string = `
// Intercept and forward in the receiving document; never overwrite a cross-origin Window.
(function () {
    'use strict';
    if (!window.atomicBridge) {
      var requests = new Map();
      var sequence = 0;
      var pageId = Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
      window.addEventListener('pagehide', function () {
        requests.forEach(function (request) { clearTimeout(request.timerId); });
        requests.clear();
      });
      window.atomicBridge = {
        debug: ${BuildProfile.DEBUG},
        postResponse(replyId, data) {
          var request = requests.get(replyId);
          if (!request) {
            console.log('replyId not found. replyId: ', replyId);
            return false;
          }
          requests.delete(replyId);
          clearTimeout(request.timerId);
          request.source.postMessage(data, request.origin);
          return true;
        },

        postEvent(data) {
          if (window !== window.top || !data || typeof data !== 'object') return false;
          var frames = document.querySelectorAll('iframe'), recipient = null, recipientOrigin = '';
          for (var i = 0; i < frames.length; i++) {
            try {
              var url = new URL(frames[i].getAttribute('src') || frames[i].src, location.href);
              if (url.protocol !== 'https:' || !url.searchParams.has('vk_app_id') ||
                  !url.searchParams.has('vk_user_id') || !url.searchParams.has('sign')) continue;
              if (recipient !== null) return false;
              recipient = frames[i].contentWindow;
              recipientOrigin = url.origin;
            } catch (_) {}
          }
          if (!recipient || !recipientOrigin) return false;
          try {
            recipient.postMessage(data, recipientOrigin);
            return true;
          } catch (_) {
            return false;
          }
        },

        onInterceptRequest(event) {
          // context.send 在顶层执行，当前只接管顶层收到的 MiniApp 请求。
          if (window !== window.top || event.origin === 'null') return false;
          var replyId = pageId + ':' + (++sequence);
          var request = { source: event.source, origin: event.origin, timerId: undefined };
          requests.set(replyId, request);
          var response;
          var accepted = false;
          try {
            response = window.HosBridge.onInterceptRequest(JSON.stringify(event.data), replyId);
            accepted = !!(response && response.intercept === true && Number.isInteger(response.timeout));
            if (accepted && response.timeout > 0 && requests.get(replyId) === request) {
              request.timerId = setTimeout(function () { requests.delete(replyId); }, response.timeout);
            }
            return accepted ? response : { intercept: false };
          } finally {
            if (!accepted) {
              clearTimeout(request.timerId);
              requests.delete(replyId);
            }
          }
        },

        onInterceptResponse(event) {
          return window.HosBridge.onInterceptResponse(JSON.stringify(event.data))
        }
      }
    }
    function interceptAndForward(event, direction) {
        var bridge = window.atomicBridge;
        if (event.data?.hooked) return;
        if (direction === 'VK2MiniApp' &&
            (event.data?.type === 'VKWebAppShowBannerAdResult' ||
                event.data?.type === 'VKWebAppShowBannerAdFailed')) {
            try {
                console.log('[VKWebAppShowBannerAd] response: ' + JSON.stringify(event.data));
            } catch (_) {
                // Logging must not affect response delivery.
            }
        }
        var resp = direction === 'MiniApp2VK' ?
            bridge.onInterceptRequest(event) : bridge.onInterceptResponse(event);
        // Defaults to the native build mode; can be overridden in this document.
        if (bridge.debug === true) {
            console.log(direction, JSON.stringify(event));
        } else {
            console.log(direction, event.data.type);
        }
        if (resp && resp.intercept) {
            event.stopImmediatePropagation();
            return
        }
        if (direction === 'VK2MiniApp') {
            event.stopImmediatePropagation();
            var responsePayload = resp && resp.data ? resp.data : event.data;
            var detail = {
                type: responsePayload.type,
                data: responsePayload.data != null ? responsePayload.data : {}
            };
            console.log('[VK AndroidBridge] dispatch VKWebAppEvent:', JSON.stringify(detail));
            window.dispatchEvent(new CustomEvent('VKWebAppEvent', { detail: detail }));
            return
        }
        if (resp && resp.data) {
            event.stopImmediatePropagation();
            resp.data.hooked = true
            var forwarded = new MessageEvent('message', {
                data: resp.data,
                origin: event.origin,
                source: event.source,
                ports: event.ports,
                lastEventId: event.lastEventId,
                bubbles: event.bubbles,
                cancelable: event.cancelable
            });
            window.dispatchEvent(forwarded);
            return
        }
    }

    function isVkHost(hostname) {
        return hostname === 'vk.ru' || hostname.endsWith('.vk.ru') ||
            hostname === 'vk.com' || hostname.endsWith('.vk.com');
    }

    function isVkOrigin(origin) {
        try {
            var parsed = new URL(origin);
            return parsed.protocol === 'https:' && isVkHost(parsed.hostname);
        } catch (_) {
            return false;
        }
    }

    function isSignedMiniAppEvent(event, appId) {
        var frames = document.querySelectorAll('iframe');
        for (var i = 0; i < frames.length; i++) {
            var frame = frames[i];
            if (frame.contentWindow !== event.source) continue;
            try {
                var frameUrl = new URL(frame.getAttribute('src') || frame.src, location.href);
                var params = frameUrl.searchParams;
                return frameUrl.origin === event.origin &&
                    (appId === undefined || params.get('vk_app_id') === appId) &&
                    params.has('vk_app_id') && params.has('vk_user_id') && params.has('sign');
            } catch (_) {
                return false;
            }
        }
        return false;
    }

    // MiniApp -> VK: intercept at the receiving VK document, including nested hosts.
    if (location.protocol === 'https:' && isVkHost(location.hostname)) {
        if (!window.__vkRequestListenerInstalled) {
            var bridge = window.atomicBridge;
            window.addEventListener('message', function (event) {
                var payload = event.data;
                if (payload && payload.type === '__mpsdk_vk_launch_params') {
                    if (window !== window.top || !Array.isArray(payload.params)) return;
                    var appId = payload.params.find(function (entry) {
                        return entry && entry.name === 'vk_app_id' && typeof entry.value === 'string';
                    });
                    if (!appId || !event.source || event.source === window ||
                        !isSignedMiniAppEvent(event, appId.value)) return;
                    event.stopImmediatePropagation();
                    try {
                        window.HosBridge.onMiniAppLaunchParams(location.href, JSON.stringify(payload.params));
                    } catch (_) {
                        console.error('[VK LaunchParams] native report unavailable');
                    }
                    return;
                }
                if (!event.source || event.source === window ||
                    !isSignedMiniAppEvent(event) ||
                    !payload || typeof payload !== 'object' ||
                    payload.type !== 'vk-connect' || typeof payload.handler !== 'string') return;

                interceptAndForward(event, 'MiniApp2VK');
            }, true);
            window.__vkRequestListenerInstalled = true;
        }
    }

    // VK -> MiniApp: intercept in the target iframe and forward to its Web callbacks.
    if (window === window.top) return;
    try {
        var miniAppUrl = new URL(location.href);
        var miniAppParams = miniAppUrl.searchParams;
        var isSignedMiniApp = miniAppParams.has('vk_app_id') &&
            miniAppParams.has('vk_user_id') && miniAppParams.has('sign');
        var originalPlatform = miniAppParams.get('vk_platform');
        if (isSignedMiniApp && originalPlatform !== 'mobile_android') {
            miniAppParams.set('vk_platform', 'mobile_android');
            history.replaceState(history.state, document.title, miniAppUrl.toString());
            console.log('[VK PlatformPatch] vk_platform patched:',
                originalPlatform, '=> mobile_android', location.href);
        } else {
            console.log('[VK PlatformPatch] skip:',
                'isSignedMiniApp=' + isSignedMiniApp,
                'vk_platform=' + originalPlatform);
        }
    } catch (error) {
        console.error('[VK PlatformPatch] failed:', error);
    }
    var params = new URL(location.href).searchParams;
    if (!params.has('vk_app_id') || !params.has('vk_user_id') || !params.has('sign')) return;
    if (!window.__vkLaunchParamsReported) {
        try {
            var launchEntries = [];
            params.forEach(function (value, name) { launchEntries.push({ name: name, value: value }); });
            window.parent.postMessage({ type: '__mpsdk_vk_launch_params', params: launchEntries }, '*');
            window.__vkLaunchParamsReported = true;
        } catch (_) {
            console.error('[VK LaunchParams] report failed');
        }
    }
    if (window.__vkReplyListenerInstalled) return;

    window.addEventListener('message', function (event) {
        var bridge = window.atomicBridge;
        if (event.source !== window.parent || !isVkOrigin(event.origin)) return;
        var payload = event.data;
        if (!payload || typeof payload !== 'object' || payload.type === 'vk-connect') return;
        var type = payload.type;
        if (typeof type !== 'string' ||
            !(type.indexOf('VKWebApp') === 0 || type === 'SetSupportedHandlers')) return;

        interceptAndForward(event, 'VK2MiniApp');
    }, true);
    window.__vkReplyListenerInstalled = true;
})();
`;

/** 为单个 WebView 会话声明注入对象和兼容脚本。 */
class VkBinding implements VendorBinding {
  readonly miniAppIdentity: VkMiniAppIdentity;
  readonly launchParams: VkLaunchParams;
  injections: BridgeInjection[] = [];
  scripts: DocumentScript[];
  private proxy: VkBridgeProxy;
  private session: MiniAppSession
  private readonly registry: VkEventRegistry;
  private disposed: boolean = false;
  private testBanner?: VkTestBannerController;
  private testNativeAd?: VkTestNativeAdController;

  constructor(session: MiniAppSession, adapter: VkAdapter) {
    this.session = session
    this.miniAppIdentity = new VkMiniAppIdentity(session.initialUrl ?? '');
    this.launchParams = new VkLaunchParams(this.miniAppIdentity);
    this.registry = new VkEventRegistry(session);
    const handlers: BaseVkEventHandler[] = [
      new VkFlashHandler(session),
      new VkMediaHandler(session),
      new VkAudioHandler(session),
      // new VkAuthTokenHandler(session, adapter),
      new VkClientMessageHandler(session, adapter),
      new VkCloseHandler(session),
      new VkHapticHandler(session),
      new VkAccelerometerHandler(session),
      new VkGyroscopeHandler(session),
      new VkDeviceMotionHandler(session),
      new VkPermissionHandler(session),
      new VkSwipeSettingsHandler(session),
      new VkViewSettingsHandler(session),
      new VkResponseInterceptor(session, this.registry),
      new VkUsersHandler(session, adapter),
      new VkPersonalCardHandler(session),
      new VkHealthHandler(session),
      new VkClientHandler(session),
    ];
    try {
      this.testBanner = adapter.createTestBanner();
      if (this.testBanner) {
        handlers.push(new VkTestBannerHandler(session, this.testBanner));
        SdkLogger.info(TAG, 'localTestBannerEnabled', { sessionId: session.id, vendorId: VK_VENDOR_ID });
      }
      this.testNativeAd = adapter.createTestNativeAd();
      if (this.testNativeAd) {
        handlers.push(new VkTestNativeAdsHandler(session, this.testNativeAd));
        SdkLogger.info(TAG, 'localTestNativeAdEnabled', { sessionId: session.id, vendorId: VK_VENDOR_ID });
      }
      this.registry.initHandler(handlers);
    } catch (error) {
      // initHandler 整批校验成功后才接管实例；失败时由绑定释放。
      handlers.forEach((handler: BaseVkEventHandler): void => {
        try {
          handler.dispose();
        } catch (_) {
          SdkLogger.warn(TAG, 'handlerDisposeFailed', { sessionId: session.id, vendorId: VK_VENDOR_ID });
        }
      });
      this.registry.dispose();
      throw MiniAppError.from(error, VENDOR_BINDING_FAILED, 'VK 模块注册失败');
    }
    this.proxy = new VkBridgeProxy(session, this.registry, this.miniAppIdentity, this.launchParams);
    this.injections = [{
      name: VK_NATIVE_PROXY_NAME,
      object: this.proxy,
      methods: ['onInterceptRequest', 'onInterceptResponse', 'onMiniAppIdentified', 'onMiniAppLaunchParams',
        'onHostGoBack', 'onHostClose',
        'supportedHandlers'],
      asyncMethods: []
    }];
    this.scripts = [
      {
        script: createVkMiniAppIdentityScript(session.initialUrl ?? '') + loginScript,
        required: true,
        scriptRules: ['*']
      },
      {
        script: vkHostPatchScript,
        required: true,
        scriptRules: ['*']
      },
      {
        script: vkAndroidBridgeScript,
        required: true,
        scriptRules: ['*']
      },
      {
        script: hookScript,
        required: true,
        scriptRules: ['*']
      }];
  }

  // 不限制网页来源；系统授权、前台状态和请求生命周期仍由 Web 层检查。
  canUseMedia(_origin: string): boolean {
    return !this.disposed;
  }

  canUseGeolocation(_origin: string): boolean {
    return !this.disposed;
  }

  onDocumentChanged(documentId: number): void {
    this.testBanner?.reset();
    this.testNativeAd?.reset();
    this.proxy.onDocumentChanged();
    SdkLogger.debug(TAG, 'documentChanged', { sessionId: this.session.id, vendorId: VK_VENDOR_ID, documentId });
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.miniAppIdentity.dispose();
    this.proxy.dispose();
    this.registry.dispose();
    this.injections = [];
    this.scripts = [];
    SdkLogger.info(TAG, 'bindingDisposed', { sessionId: this.session.id, vendorId: VK_VENDOR_ID });
  }
}

/** 创建负责 VK 协议和工具调用的独立注入对象。 */
export class VkVendor implements Vendor {
  readonly vendorId: string = VK_VENDOR_ID;

  createDefaultAdapter(): VkAdapter {
    return new VkAdapter();
  }

  createBinding(session: MiniAppSession): VendorBinding {
    const adapter = session.getAdapter()
    if (!(adapter instanceof VkAdapter)) {
      throw new MiniAppError(INVALID_ARGUMENT, 'VK 厂商需要 VkAdapter');
    }
    const binding = new VkBinding(session, adapter);
    SdkLogger.info(TAG, 'bindingCreated', { sessionId: session.id, vendorId: this.vendorId });
    return binding;
  }
}
