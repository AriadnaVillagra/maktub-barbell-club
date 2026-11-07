'use strict';

// App-shell service worker. Scope = the directory it is served from, i.e. the
// base path of the deployment (/maktub-barbell-club/ on GitHub Pages).
//
// - Same-origin GETs inside the scope: cache-first from the shell cache, falling
//   back to the network.
// - Everything else (API on *.run.app, other origins, non-GET): not intercepted,
//   so it goes straight to the network. The day's data is stored by the app (E7).
//
// BUILD_ID and PRECACHE_URLS are filled in after `flutter build web` by
// scripts/sellar-service-worker.sh. BUILD_ID changes whenever any shipped file
// changes, so each deploy produces a byte-different worker: the browser installs
// it, it opens a fresh cache, and old caches are deleted on activate.
const BUILD_ID = '__BUILD_ID__';
const PRECACHE_URLS = ['__PRECACHE_URLS__'];

const CACHE_PREFIX = 'maktub-shell-';
const CACHE_NAME = CACHE_PREFIX + BUILD_ID;
const INDEX_URL = new URL('./', self.registration.scope).href;

// An unstamped copy (flutter run, plain build) must not cache anything.
const stamped = BUILD_ID !== '__BUILD_ID__';

self.addEventListener('install', (event) => {
  if (!stamped) return;
  // No skipWaiting: an update waits until every tab/PWA window is closed, so a
  // running page never mixes files of two builds.
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      // 'reload' bypasses the HTTP cache so the cache matches this build.
      cache.addAll(PRECACHE_URLS.map((u) => new Request(u, { cache: 'reload' })))
    )
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      if (!stamped) {
        await self.registration.unregister();
        return;
      }
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((n) => n.startsWith(CACHE_PREFIX) && n !== CACHE_NAME)
          .map((n) => caches.delete(n))
      );
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (!stamped || request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (!url.href.startsWith(self.registration.scope)) return;
  event.respondWith(respond(request));
});

async function respond(request) {
  const cache = await caches.open(CACHE_NAME);
  // Navigations always get the shell page (hash routing: a single document).
  const cached = await cache.match(
    request.mode === 'navigate' ? INDEX_URL : request,
    { ignoreSearch: true }
  );
  if (cached) return cached;
  const response = await fetch(request);
  if (response.ok && response.type === 'basic') {
    cache.put(request, response.clone());
  }
  return response;
}
