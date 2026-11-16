/** Debug-only, user-triggered test of the real LIFF API; never changes client identity. */
export function lineBridgeDiagnostics(appId: string): string {
  return `(function () {
    if (window !== window.top || document.getElementById('mp-host-scan-test')) return;
    var attempts = 0;
    var stopped = false;
    var timer;
    window.addEventListener('pagehide', function () { stopped = true; clearTimeout(timer); }, { once: true });
    function mount() {
    if (stopped || document.getElementById('mp-host-scan-test')) return;
    var liff = window.liff;
    if (!liff || !liff.ready || typeof liff.getContext !== 'function') {
      if (++attempts < 100) timer = setTimeout(mount, 100);
      return;
    }
    Promise.resolve(liff.ready).then(function () {
      var context = liff.getContext();
      if (!context || context.liffId !== ${JSON.stringify(appId)}) {
        console.debug('[Host scan test] ID_NOT_READY');
        return;
      }
      if (stopped) return;
      var panel = document.createElement('section');
      panel.id = 'mp-host-scan-test';
      panel.style.cssText = 'position:fixed;bottom:12px;left:12px;right:12px;z-index:2147483647;padding:12px;background:#fff;border:2px solid #087f5b;border-radius:12px;color:#142b24;font:14px sans-serif;box-shadow:0 4px 20px #0003';
      var label = document.createElement('div');
      label.textContent = '宿主调试 · 真实 LIFF 原生扫码 / Native scan test';
      var result = document.createElement('div');
      result.style.cssText = 'padding:8px 0;word-break:break-all;max-height:80px;overflow:auto';
      result.textContent = '仅测试扩展桥接，不改变 LINE 客户端状态。';
      var scan = document.createElement('button');
      scan.textContent = '原生扫码 / Scan';
      scan.style.cssText = 'padding:12px;margin-right:12px';
      scan.onclick = async function () {
        scan.disabled = true;
        result.textContent = '等待系统扫码结果 / Scanning…';
        try {
          var value = await liff.scanCodeV2();
          result.textContent = '扫码结果 / Result: ' + value.value;
        } catch (error) {
          result.textContent = '扫码未完成 / Scan failed: ' + (error.code || 'UNKNOWN');
        } finally { scan.disabled = false; }
      };
      var close = document.createElement('button');
      close.textContent = '隐藏 / Hide';
      close.style.cssText = 'padding:12px';
      close.onclick = function () { panel.remove(); };
      panel.appendChild(label); panel.appendChild(result);
      panel.appendChild(scan); panel.appendChild(close);
      document.body.appendChild(panel);
    }).catch(function () { console.debug('[Host scan test] INIT_UNAVAILABLE'); });
    }
    mount();
  })();`;
}
