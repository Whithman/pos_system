<?php
// ═══════════════════════════════════════════════════════════════════════════
// POS SERVICE WORKER — device-side image cache ("install once, load fast")
// ═══════════════════════════════════════════════════════════════════════════
// Served same-origin from the app root so browsers actually accept the
// registration (a blob-URL worker is silently rejected). Strategies:
//   • Product photos & logo  → cache-FIRST in a dedicated, size-trimmed cache:
//     after the first view, images load instantly from the device with zero
//     network — even offline. URLs are versioned (?v=updated_at / timestamped
//     cloud paths), so a replaced photo is a new URL and never serves stale.
//   • App HTML (navigations) → network-FIRST so deploys arrive immediately,
//     with the last copy kept for offline use.
//   • CDN libraries          → cache-first (they never change).
//   • API data (?api=…)      → always the network, never cached — prices,
//     stock and sales must be live.
header('Content-Type: application/javascript; charset=utf-8');
header('Cache-Control: no-cache');
header('Service-Worker-Allowed: /');
?>
const SHELL = 'pos-shell-v2';
const IMGS = 'pos-img-v1';
const IMG_LIMIT = 400; // ~a few hundred photos max on the device

self.addEventListener('install', e => {
    e.waitUntil(caches.open(SHELL).then(c => c.addAll([
        self.location.origin + '/',
        'https://cdn.jsdelivr.net/npm/jsbarcode@3.11.6/dist/JsBarcode.all.min.js',
        'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.min.js'
    ]).catch(() => {})));
    self.skipWaiting();
});

self.addEventListener('activate', e => {
    e.waitUntil(
        caches.keys()
            .then(keys => Promise.all(keys.filter(k => k !== SHELL && k !== IMGS).map(k => caches.delete(k))))
            .then(() => self.clients.claim())
    );
});

function isImageRequest(url, req) {
    if (req.method !== 'GET') return false;
    if (url.pathname.includes('get_product_image')) return true;                       // product photos & logo
    if (url.hostname.endsWith('.supabase.co') && url.pathname.includes('/storage/v1/object/public/')) return true; // Supabase CDN images
    if (url.hostname.endsWith('.cloudinary.com') && url.pathname.includes('/image/upload/')) return true;          // legacy Cloudinary images
    return false;
}

async function trimCache(cacheName, max) {
    const cache = await caches.open(cacheName);
    const keys = await cache.keys();
    while (keys.length > max) {
        await cache.delete(keys[0]); // drop the oldest-cached entry first
        keys.shift();
    }
}

self.addEventListener('fetch', e => {
    const req = e.request;
    const url = new URL(req.url);

    // State-changing calls (login, save, sell…) — always live, never cached.
    if (req.method !== 'GET') {
        e.respondWith(fetch(req).catch(() =>
            new Response(JSON.stringify({ success: false, error: 'Offline' }),
                { headers: { 'Content-Type': 'application/json' }, status: 503 })
        ));
        return;
    }

    // ── IMAGES: cache-first (instant after first view, works offline) ──
    if (isImageRequest(url, req)) {
        e.respondWith((async () => {
            const cache = await caches.open(IMGS);
            const hit = await cache.match(req);
            if (hit) return hit;
            try {
                const resp = await fetch(req);
                if (resp && (resp.status === 200 || resp.type === 'opaque')) {
                    await cache.put(req, resp.clone());
                    trimCache(IMGS, IMG_LIMIT);
                }
                return resp;
            } catch (err) {
                // Offline and never seen before — nothing we can do.
                return Response.error();
            }
        })());
        return;
    }

    // ── APP HTML: network-first so every deploy arrives immediately ──
    if (req.mode === 'navigate') {
        e.respondWith((async () => {
            try {
                const resp = await fetch(req);
                const cache = await caches.open(SHELL);
                cache.put(self.location.origin + '/', resp.clone());
                return resp;
            } catch (err) {
                const cache = await caches.open(SHELL);
                return (await cache.match(self.location.origin + '/')) || Response.error();
            }
        })());
        return;
    }

    // ── CDN libraries: cache-first (immutable) ──
    if (url.hostname !== location.hostname) {
        e.respondWith((async () => {
            const cache = await caches.open(SHELL);
            const hit = await cache.match(req);
            if (hit) return hit;
            try {
                const resp = await fetch(req);
                if (resp && resp.status === 200) await cache.put(req, resp.clone());
                return resp;
            } catch (err) {
                return hit || Response.error();
            }
        })());
        return;
    }

    // ── Same-origin data GETs (?api=get_products etc.): plain network ──
    // Deliberately NOT cached — stock counts, prices and sales must be live.
});
