const SHELL = 'pos-shell-v5';
const IMGS = 'pos-img-v2';
const IMG_LIMIT = 400; // ~a few hundred photos max on the device

self.addEventListener('install', e => {
    e.waitUntil(caches.open(SHELL).then(c => c.addAll([
        self.location.origin + '/',
        self.location.origin + '/manifest.json',
        self.location.origin + '/assets/icon-192.png',
        self.location.origin + '/assets/icon-512.png',
        self.location.origin + '/assets/icon-192-maskable.png',
        self.location.origin + '/assets/icon-512-maskable.png',
        self.location.origin + '/assets/default-logo.png',
        'https://cdn.jsdelivr.net/npm/jsbarcode@3.11.6/dist/JsBarcode.all.min.js',
        'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.min.js'
    ]).catch(() => { })));
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
    if (url.pathname.includes('get_product_image')) return true;
    if (url.pathname.includes('/assets/') && (url.pathname.endsWith('.png') || url.pathname.endsWith('.webp') || url.pathname.endsWith('.jpg'))) return true;
    if (url.hostname.endsWith('.supabase.co') && url.pathname.includes('/storage/v1/object/public/')) return true;
    if (url.hostname.endsWith('.cloudinary.com') && url.pathname.includes('/image/upload/')) return true;
    return false;
}

async function trimCache(cacheName, max) {
    const cache = await caches.open(cacheName);
    const keys = await cache.keys();
    while (keys.length > max) {
        await cache.delete(keys[0]);
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

    // Dynamic API requests (?api=...) — always live network, never cached by SW.
    if (url.searchParams.has('api')) {
        return; // pass straight through to network
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
                return Response.error();
            }
        })());
        return;
    }

    // ── APP HTML NAVIGATION: network-first with fast timeout fallback ──
    if (req.mode === 'navigate') {
        e.respondWith((async () => {
            const cache = await caches.open(SHELL);

            // Never cache logout transitions
            if (url.searchParams.get('page') === 'logout') {
                return fetch(req).catch(() => Response.redirect(self.location.origin + '/?page=login', 302));
            }

            try {
                const ctrl = new AbortController();
                // 5-second timeout: if server/Render takes longer than 5s to respond, fall back to cached shell instantly
                const timer = setTimeout(() => ctrl.abort(), 5000);
                const resp = await fetch(req, { signal: ctrl.signal });
                clearTimeout(timer);

                if (resp && resp.status === 200) {
                    cache.put(req, resp.clone());
                    // Keep root entry updated if visiting dashboard or root
                    if (url.pathname === '/' && (!url.search || url.search === '?page=dashboard')) {
                        cache.put(self.location.origin + '/', resp.clone());
                    }
                }
                return resp;
            } catch (err) {
                // If network hangs, times out, or device is offline, serve cached page for this URL or root shell
                const hit = (await cache.match(req)) || (await cache.match(self.location.origin + '/'));
                if (hit) return hit;
                return Response.error();
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
});
