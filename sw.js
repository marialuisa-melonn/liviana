/* Liviana · service worker
   v2 — arregla el caché pegado.

   El bug de v1: `fetch(request)` pasa por el caché HTTP del navegador, y GitHub Pages
   manda cache-control: max-age=600. O sea que "ir a la red" devolvía igual la copia
   vieja hasta 10 minutos después, y al abrir la app desde la pantalla de inicio
   podía quedarse pegada mucho más. Ahora el HTML se pide con cache:"no-store",
   que salta ese caché y siempre pregunta al servidor de verdad. */
const C = "liviana-v2";
const ASSETS = ["./", "./index.html", "./manifest.json", "./icon-192.png", "./icon-512.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(C).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== C).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

const esHTML = req =>
  req.mode === "navigate" ||
  (req.headers.get("accept") || "").includes("text/html");

self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;

  // El HTML SIEMPRE se pide fresco, saltando el caché HTTP del navegador.
  if (esHTML(e.request)) {
    e.respondWith(
      fetch(e.request, { cache: "no-store" })
        .then(r => {
          const cp = r.clone();
          caches.open(C).then(c => c.put("./index.html", cp)).catch(() => {});
          return r;
        })
        .catch(() => caches.match("./index.html").then(m => m || caches.match("./")))
    );
    return;
  }

  // El resto (iconos, manifest) sí puede salir del caché primero: no cambia.
  e.respondWith(
    caches.match(e.request).then(m => m ||
      fetch(e.request).then(r => {
        const cp = r.clone();
        caches.open(C).then(c => c.put(e.request, cp)).catch(() => {});
        return r;
      })
    )
  );
});

// Permite que la app pida "actívate ya" sin esperar a que cierre todas las pestañas.
self.addEventListener("message", e => { if (e.data === "skipWaiting") self.skipWaiting(); });
