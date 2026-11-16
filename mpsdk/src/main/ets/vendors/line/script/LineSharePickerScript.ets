import { LineBridgeErrorCode } from '../LineErrorCode';
import { LINE_SHARE_PICKER_BRIDGE_NAME } from '../LineConstants';
import { LINE_SHARE_PICKER_URL } from '../scheme/LineSchemeConstants';

/** 只由 WEB_HOOK 安装；官方 LIFF 继续负责 OTT 与结果轮询。 */
export function createLineSharePickerInstaller(): string {
  return `function installSharePicker(liff, observeMethod) {
    var pickerUrl = '${LINE_SHARE_PICKER_URL}';
    var pickerOrigin = new URL(pickerUrl).origin;
    var active;
    function failure(message) {
      var error = new Error(message);
      error.name = 'LiffError';
      error.code = '${LineBridgeErrorCode.FORBIDDEN}';
      return error;
    }
    function cleanup(call) {
      // UI 可先关闭，但官方 Promise 未结束前仍占用调用，避免迟到 OTT 串入下一次分享。
      if (active === call && !call.officialPending) active = undefined;
      if (call.done) return;
      call.done = true;
      clearInterval(call.timer);
      clearTimeout(call.deadline);
      window.removeEventListener('message', call.onMessage);
      window.removeEventListener('pagehide', call.onExit);
      call.abort.abort();
      if (call.popup && !call.popup.closed) call.popup.close();
    }
    function fail(call, error) {
      cleanup(call);
      call.reject(error);
    }
    function cancel(call) {
      if (call.cancelling || !call.ott || call.done) return;
      call.cancelling = true;
      // 通知服务端取消，让官方结果轮询结束；不伪造分享成功或取消回包。
      var resultUrl = pickerUrl + '/result?liffId=' + encodeURIComponent(call.liffId) +
        '&ott=' + encodeURIComponent(call.ott);
      fetch(resultUrl, {
        method: 'POST', signal: call.abort.signal,
        headers: { Accept: 'application/json', 'Content-Type': 'application/x-www-form-urlencoded' },
        body: 'result=CANCEL'
      }).then(function (response) {
        if (!response.ok) throw failure('Unable to cancel share target picker.');
        return response.json();
      }).then(function (result) {
        if (result.status !== 'ok') throw failure('Unable to cancel share target picker.');
      }).catch(function (error) { fail(call, error); });
    }
    window.${LINE_SHARE_PICKER_BRIDGE_NAME} = {
      accept: function (request) {
        var call = active;
        if (!call || call.done || call.payload || request.liffId !== call.liffId ||
          typeof request.ott !== 'string' || !request.ott) return false;
        var payload;
        try {
          payload = JSON.parse(request.data);
          // 原生侧校验所属 Session；这里校验协议是否对应当前预建窗口的这次调用。
          if (!payload || !payload.referrer || payload.referrer.liffId !== call.liffId ||
            new URL(payload.referrer.url).origin !== location.origin ||
            JSON.stringify(payload.messages) !== call.messagesJson ||
            payload.isMultiple !== call.isMultiple) return false;
        } catch (_) { return false; }
        call.ott = request.ott;
        call.payload = payload;
        if (call.popup.closed) {
          cancel(call);
        } else {
          call.popup.location.href = pickerUrl + '?liffId=' + encodeURIComponent(call.liffId) +
            '&ott=' + encodeURIComponent(call.ott);
        }
        return true;
      }
    };
    observeMethod(liff, 'shareTargetPicker', function (getOriginal) {
      return function () {
        var args = Array.prototype.slice.call(arguments);
        // executor 同步执行，保留开窗所需的用户手势；上下文和序列化异常也统一转为 Promise 拒绝。
        return new Promise(function (resolve, reject) {
          if (active) throw failure('Share target picker is already open.');
          var original = getOriginal();
          if (typeof original !== 'function') throw failure('Share target picker is unavailable.');
          var context = liff.getContext();
          if (!context || !context.liffId) throw failure('LIFF context is unavailable.');
          var call = {
            liffId: context.liffId, messagesJson: JSON.stringify(args[0]),
            isMultiple: !args[1] || args[1].isMultiple === undefined ? true : args[1].isMultiple,
            done: false, officialPending: false, cancelling: false,
            abort: new AbortController(), reject: reject
          };
          active = call;
          try {
            call.popup = window.open('', 'liffpopup', 'width=480,height=640,menubar=no,toolbar=no,scrollbars=yes');
            if (!call.popup) throw failure('Unable to open share target picker.');
            // LIFF 客户端分支不安装网页握手监听，这里只补齐预建窗口与官方域名之间的通信。
            call.onMessage = function (event) {
              if (active !== call || call.done || !call.payload || event.source !== call.popup ||
                event.origin !== pickerOrigin || !event.data || event.data.name !== 'receivedHealthcheck') return;
              call.popup.postMessage({ name: 'ready', body: call.payload }, pickerOrigin);
            };
            call.onExit = function () { fail(call, failure('Source document is no longer active.')); };
            window.addEventListener('message', call.onMessage);
            window.addEventListener('pagehide', call.onExit);
            call.timer = setInterval(function () {
              if (call.done) return;
              if (call.popup.closed) { cancel(call); return; }
              if (call.payload) call.popup.postMessage({ name: 'healthcheck', body: undefined }, pickerOrigin);
            }, 1000);
            call.deadline = setTimeout(function () { fail(call, failure('Share target picker timed out.')); }, 600000);
            call.officialPending = true;
            Promise.resolve(original.apply(liff, args)).finally(function () {
              call.officialPending = false;
              cleanup(call);
            }).then(resolve, reject);
          } catch (error) {
            call.officialPending = false;
            fail(call, error);
          }
        });
      };
    });
  }`;
}
