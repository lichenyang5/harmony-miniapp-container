/** Replace only the selected VK app's centered loading image, inside the host WebView. */
export function vkTransitionIcon(appId: string, imageDataUrl: string): string {
  if (!/^[0-9]+$/.test(appId) || !imageDataUrl.startsWith('data:image/png;base64,')) {
    throw new Error('Invalid transition icon configuration');
  }
  return `(function () {
    if (window !== window.top || location.protocol !== 'https:' ||
      !/^(m\\.)?vk\\.(ru|com)$/.test(location.hostname) || location.port) return;
    var entry = new RegExp('^/(?:games/)?app' + ${JSON.stringify(appId)} + '/?$');
    var icon = ${JSON.stringify(imageDataUrl)};
    var stopped = false;
    var observer;
    function update() {
      if (stopped || !entry.test(location.pathname)) return;
      var images = document.querySelectorAll('img,[style*="background-image"]');
      var candidates = [];
      for (var index = 0; index < images.length; index++) {
        var node = images[index], rect = node.getBoundingClientRect();
        if (rect.width < 64 || rect.width > 160 || Math.abs(rect.width - rect.height) > 4 ||
          Math.abs(rect.left + rect.width / 2 - window.innerWidth / 2) > 12 ||
          Math.abs(rect.top + rect.height / 2 - window.innerHeight / 2) > 28) continue;
        if (node.tagName !== 'IMG' && getComputedStyle(node).backgroundImage === 'none') continue;
        candidates.push(node);
      }
      // Ambiguous layouts are left untouched; business iframe images are never inspected.
      if (candidates.length !== 1) return;
      var target = candidates[0];
      if (target.tagName === 'IMG') {
        if (target.getAttribute('src') === icon && !target.getAttribute('srcset')) return;
        target.removeAttribute('srcset');
        target.setAttribute('src', icon);
        target.style.objectFit = 'contain';
        console.debug('[Host transition icon] replaced');
      } else {
        var background = 'url("' + icon + '")';
        if (target.style.backgroundImage === background) return;
        target.style.backgroundImage = background;
        target.style.backgroundSize = 'contain';
        target.style.backgroundRepeat = 'no-repeat';
        target.style.backgroundPosition = 'center';
        console.debug('[Host transition icon] replaced');
      }
    }
    observer = new MutationObserver(update);
    observer.observe(document, { childList: true, subtree: true, attributes: true,
      attributeFilter: ['src', 'srcset', 'style', 'class'] });
    document.addEventListener('load', update, true);
    window.addEventListener('resize', update);
    window.addEventListener('pagehide', function () {
      stopped = true;
      observer.disconnect();
      document.removeEventListener('load', update, true);
      window.removeEventListener('resize', update);
    }, { once: true });
    update();
  })();`;
}
