const CACHE_NAME = "pasar-hanakau-buyer-shell-v1";
const APP_SHELL = ["./", "./manifest.webmanifest", "../icons/icon.svg", "../icons/icon-192.png", "../icons/icon-512.png", "../icons/logo-pasar-hanakau.png"];

self.addEventListener("install", event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL);
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key !== CACHE_NAME && key.startsWith("pasar-hanakau-buyer-shell-")).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", event => {
  if (event.request.method !== "GET" || new URL(event.request.url).origin !== self.location.origin) return;
  event.respondWith((async () => {
    try {
      const response = await fetch(event.request, event.request.mode === "navigate" ? { cache: "no-cache" } : {});
      if (response && response.ok) {
        const cache = await caches.open(CACHE_NAME);
        cache.put(event.request, response.clone()).catch(() => {});
      }
      return response;
    } catch {
      const cached = await caches.match(event.request);
      if (cached) return cached;
      if (event.request.mode === "navigate") {
        return caches.match("./");
      }
      return Response.error();
    }
  })());
});
