/*
  coi-serviceworker.js
  Service worker to set COOP/COEP headers to allow cross-origin isolation
*/
(function () {
  if (typeof window === 'undefined') {
    // Service worker context
    self.addEventListener('install', () => self.skipWaiting());
    self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
    self.addEventListener('fetch', (event) => {
      // Intercept navigation requests to inject headers
      if (event.request.mode === 'navigate') {
        event.respondWith(
          fetch(event.request).then((response) => {
            const newHeaders = new Headers(response.headers);
            newHeaders.set('Cross-Origin-Opener-Policy', 'same-origin');
            newHeaders.set('Cross-Origin-Embedder-Policy', 'require-corp');
            return new Response(response.body, {
              status: response.status,
              statusText: response.statusText,
              headers: newHeaders,
            });
          })
        );
      } else {
        event.respondWith(fetch(event.request));
      }
    });
  } else {
    // Window context - Register the service worker
    if (window.crossOriginIsolated !== true) {
      navigator.serviceWorker.register(window.document.currentScript.src);
    }
  }
})();
