/* ──────────────────────────────────────────────────────────────────────────
   Waypoints service worker
   ──────────────────────────────────────────────────────────────────────────
   The app is most needed exactly where a connection isn't: on a 20-hour
   flight, in an airport, on foreign mobile data. Without this the page itself
   is a network fetch, so with no signal you don't get a degraded app — you get
   nothing at all.

   Strategy, by what the thing is:
     · the page      network-first, cache fallback   (deploys land; offline works)
     · fonts, CDN JS cache-first, network fallback   (immutable, versioned URLs)
     · Supabase      never touched                   (auth + live data; a stale
                                                      cached reply would be a lie.
                                                      The app keeps its own
                                                      localStorage mirror instead.)
   ────────────────────────────────────────────────────────────────────────── */

var VERSION = 'waypoints-v3';
var SHELL   = VERSION + '-shell';
var ASSETS  = VERSION + '-assets';

/* Cached on install so the very first offline open works even if the person
   never visited these sub-resources while online. */
var PRECACHE = [
  './waypoints.html',
  './manifest.webmanifest',
  './icon-192.png',
  './icon-512.png',
  './apple-touch-icon.png',
  // Cross-origin, and both matter on the first offline open: the worker is not
  // yet controlling the page when these are first requested, so waiting for a
  // second visit to catch them is how you arrive on a plane without them.
  // Without the Supabase library the app silently falls back to local-only.
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
  'https://fonts.googleapis.com/css2?family=Spectral:ital,wght@0,400;0,500;0,600;0,700;0,900;1,400;1,500&family=Karla:wght@300;400;500;600;700&family=IBM+Plex+Mono:wght@400;500;600&display=swap'
];

self.addEventListener('install', function(e){
  e.waitUntil(
    caches.open(SHELL)
      // Individually, so one failure (my-trips.local.js is absent in
      // production) can't reject the whole install.
      .then(function(c){ return Promise.all(PRECACHE.map(function(u){
        // cache.add() would store the redirected response verbatim, which is
        // unusable for a navigation — fetch and clean it first.
        return fetch(u).then(unredirected).then(function(res){
          if (res && (res.ok || res.type === 'opaque')) return c.put(u, res);
        }).catch(function(){});
      })); })
      .then(function(){ return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function(e){
  e.waitUntil(
    caches.keys().then(function(keys){
      return Promise.all(keys.map(function(k){
        if (k.indexOf(VERSION) !== 0) return caches.delete(k);
      }));
    }).then(function(){ return self.clients.claim(); })
  );
});

function isCacheableAsset(url){
  return url.origin === 'https://fonts.googleapis.com' ||
         url.origin === 'https://fonts.gstatic.com'   ||
         url.origin === 'https://cdn.jsdelivr.net'    ||
         (url.origin === self.location.origin && /\.(png|webmanifest|css|js)$/.test(url.pathname));
}

/* A Response with redirected:true cannot legally be returned for a navigation —
   the browser rejects it. Static hosts rewrite ".html" away with a 301, so the
   copy we fetch is frequently redirected. Rebuild it as a plain 200. */
function unredirected(res){
  if (!res.redirected) return Promise.resolve(res);
  return res.text().then(function(body){
    return new Response(body, {
      status: 200,
      statusText: 'OK',
      headers: { 'Content-Type': res.headers.get('Content-Type') || 'text/html; charset=utf-8' }
    });
  });
}

/* The page may be addressed with or without the extension depending on the
   host, so look under both rather than assuming one. */
function cachedShell(){
  return caches.match('./waypoints.html', {ignoreSearch:true}).then(function(hit){
    return hit || caches.match('./waypoints', {ignoreSearch:true});
  }).then(function(hit){
    return hit || caches.match('./index.html', {ignoreSearch:true});
  });
}

self.addEventListener('fetch', function(e){
  var req = e.request;
  if (req.method !== 'GET') return;

  var url;
  try { url = new URL(req.url); } catch (err) { return; }

  // Never intercept Supabase: auth tokens and live rows must not come from a
  // cache, and a failure here is exactly what tells the app it is offline.
  if (url.hostname.indexOf('supabase.co') !== -1) return;

  // request.mode is the reliable signal for "this is a page load" — far better
  // than guessing from the path, which varies by host.
  if (req.mode === 'navigate'){
    e.respondWith(
      fetch(req)
        .then(unredirected)
        .then(function(res){
          if (res && res.ok){
            var copy = res.clone();
            caches.open(SHELL).then(function(c){ c.put('./waypoints.html', copy); });
          }
          return res;
        })
        .catch(function(){
          return cachedShell().then(function(hit){
            return hit || new Response(
              '<h1>Offline</h1><p>No cached copy of Waypoints on this device yet. Open it once with a connection.</p>',
              { status: 503, headers: {'Content-Type':'text/html; charset=utf-8'} }
            );
          });
        })
    );
    return;
  }

  if (isCacheableAsset(url)){
    e.respondWith(
      caches.match(req).then(function(hit){
        if (hit) return hit;
        return fetch(req).then(function(res){
          if (res && (res.ok || res.type === 'opaque')){
            var copy = res.clone();
            caches.open(ASSETS).then(function(c){ c.put(req, copy); });
          }
          return res;
        }).catch(function(){ return hit || Response.error(); });
      })
    );
  }
});

/* Lets the page ask a waiting worker to take over immediately. */
self.addEventListener('message', function(e){
  if (e.data === 'skipWaiting') self.skipWaiting();
});
