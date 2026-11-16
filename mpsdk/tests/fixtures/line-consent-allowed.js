// Captured from the official consent POST success document. No account data or URL parameters.
(function () {
    const allowUrl = null;
    const allowScript = "line.onUserAllowed()";
    if (allowUrl) {
        location.href = allowUrl;
    } else {
        const autoAllow = function () {
            if (typeof window.line !== 'undefined') {
                eval(allowScript);
            } else {
                setTimeout(autoAllow, 100);
            }
        };
        window.addEventListener('load', autoAllow, false);
    }
})();
