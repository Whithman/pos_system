/*
 * Service worker for POS System.
 *
 * SCOPE OF WHAT THIS CACHES — deliberately narrow:
 *   - Truly static files only: app icons, the login/landing background
 *     image, and Google Fonts. These never change per-request, so
 *     caching them is 100% safe and makes repeat visits noticeably
 *     faster (no re-download of the same bytes every time).
 *
 * WHAT THIS NEVER CACHES — on purpose:
 *   - Any request containing "api=" (cart, sales, stock, cash float,
 *     etc.) — this is live transactional data. Cashier, admin, and
 *     warehouse devices must always see the current server state, not
 *     a cached snapshot.
 *   - Any full page navigation (?page=dashboard, ?page=products, ...)
 *     — these are server-rendered PHP pages that can contain
 *     session-specific and live data. They always go straight to the
 *     network so what's on screen is never stale.
 *   - Any non-GET request (POST/PUT/DELETE) — never cached, ever.
 *
 * Bump CACHE_VERSION whenever the static asset list below changes, so
 * old caches get cleaned up automatically on the next activate.
 */

const CACHE_VERSION = 'pos-static-v3';

const STATIC_ASSET_PATTERNS = [
    /\/icons\/icon-.*\.png$/,
    /\/assets\/.*\.(webp|png|jpe?g|svg|ico)$/,
    // Product photos and the shop logo — safe to cache indefinitely because
    // the app writes a NEW timestamped filename every time one is replaced
    // (e.g. p123_1755999999.jpg, logo_1755999999.png) and deletes the old
    // file server-side. So a cached copy can never go stale under the same
    // URL; a replaced photo always has a brand-new URL to fetch fresh.
    /\/uploads\/products\/.*\.(webp|png|jpe?g|gif)$/,
    /\/uploads\/shop\/.*\.(webp|png|jpe?g|gif)$/,
    // Product photos + shop logo now live in Supabase Storage (survives
    // Render redeploys, unlike local disk — see saveProductImageFile() in
    // index.php). Same safety argument as above: every upload gets a new
    // timestamped filename, so a cached copy can never go stale.
    /^https:\/\/[a-z0-9-]+\.supabase\.co\/storage\/v1\/object\/public\//i,
    /^https:\/\/fonts\.googleapis\.com\//,
    /^https:\/\/fonts\.gstatic\.com\//,
];

function isCacheableStaticAsset(request) {
    if (request.method !== 'GET') return false;
    const url = request.url;
    return STATIC_ASSET_PATTERNS.some((re) => re.test(url));
}

function isLiveDataRequest(request) {
    const url = new URL(request.url);
    if (request.method !== 'GET') return true; // never cache writes
    if (url.searchParams.has('api')) return true; // live API calls
    if (url.searchParams.has('page')) return true; // server-rendered pages
    if (request.mode === 'navigate') return true; // any full navigation
    return false;
}

self.addEventListener('install', (event) => {
    // Activate this worker as soon as it finishes installing, instead
    // of waiting for all old tabs to close.
    self.skipWaiting();
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((keys) =>
            Promise.all(
                keys
                    .filter((key) => key !== CACHE_VERSION)
                    .map((key) => caches.delete(key))
            )
        ).then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', (event) => {
    const { request } = event;

    // Live/transactional/page requests: always go to the network,
    // untouched. Do not intercept — let the browser handle it normally.
    if (isLiveDataRequest(request)) {
        return;
    }

    // Static assets: cache-first, falling back to network, then
    // saving a fresh copy into the cache for next time.
    if (isCacheableStaticAsset(request)) {
        event.respondWith(
            caches.open(CACHE_VERSION).then((cache) =>
                cache.match(request).then((cached) => {
                    if (cached) return cached;
                    return fetch(request).then((response) => {
                        // Only cache successful, basic/opaque responses.
                        if (response && (response.status === 200 || response.type === 'opaque')) {
                            cache.put(request, response.clone());
                        }
                        return response;
                    }).catch(() => cached); // offline + not cached yet: let it fail naturally
                })
            )
        );
    }
    // Anything else (not matched above): default browser behavior.
});
