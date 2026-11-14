const CACHE_NAME = "pasar-hanakau-shell-v6";
const APP_SHELL = ["./", "./manifest.webmanifest", "./icons/icon.svg", "./icons/icon-192.png", "./icons/icon-512.png"];

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
    await Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key)));
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
        const shell = await caches.match("./");
        if (shell) return shell;
      }
      return new Response("Anda sedang offline. Periksa koneksi internet lalu coba lagi.", {
        status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" }
      });
    }
  })());
});

self.addEventListener("push", event => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; }
  catch { payload = { body: event.data ? event.data.text() : "Ada pembaruan di Pasar Hanakau." }; }
  const title = payload.title || "Pasar Hanakau";
  const options = {
    body: payload.body || "Ada pembaruan pesanan untuk Anda.",
    icon: payload.icon || "./icons/icon-192.png",
    
    tag: payload.tag || "pasar-hanakau-update",
    data: { url: payload.url || "./" },
    renotify: Boolean(payload.renotify)
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  let targetUrl;
  try {
    targetUrl = new URL(event.notification.data?.url || "./", self.registration.scope);
  } catch {
    targetUrl = new URL("./", self.registration.scope);
  }
  const scopeUrl = new URL(self.registration.scope);
  if (targetUrl.origin !== scopeUrl.origin || !targetUrl.pathname.startsWith(scopeUrl.pathname)) {
    targetUrl = new URL("./", self.registration.scope);
  }
  const target = targetUrl.href;
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of windows) {
      if (client.url.startsWith(self.registration.scope) && "focus" in client) {
        await client.focus();
        if ("navigate" in client) await client.navigate(target);
        return;
      }
    }
    if (clients.openWindow) await clients.openWindow(target);
  })());
});
