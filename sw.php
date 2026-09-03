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
const SHELL = 'pos-shell-v6';
const IMGS = 'pos-img-v2';
const IMG_LIMIT = 400; // ~a few hundred photos max on the device
const BASE = new URL('./', self.location).href;

self.addEventListener('install', e => {
e.waitUntil(caches.open(SHELL).then(c => c.addAll([
BASE,
new URL('manifest.json', BASE).href,
new URL('assets/icon-192.png', BASE).href,
new URL('assets/icon-512.png', BASE).href,
new URL('assets/icon-192-maskable.png', BASE).href,
new URL('assets/icon-512-maskable.png', BASE).href,
new URL('assets/default-logo.png', BASE).href,
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

self.addEventListener('message', e => {
if (e.data === 'skipWaiting') {
self.skipWaiting();
}
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

// ── APP HTML NAVIGATION: network-first with safe offline fallback ──
if (req.mode === 'navigate') {
e.respondWith((async () => {
// Never cache or intercept logout transitions
if (url.searchParams.get('page') === 'logout') {
return fetch(req).catch(() => Response.redirect(new URL('./?page=login', self.location).href, 302));
}

const cache = await caches.open(SHELL);

try {
// Direct live network request — DO NOT pass { signal } or RequestInit to avoid WHATWG TypeError
const resp = await fetch(req);
if (resp && resp.status === 200) {
cache.put(req, resp.clone());
}
return resp;
} catch (err) {
// If offline or network disconnected:
// 1. Check if the user has already visited and cached this exact page URL
const hit = await cache.match(req);
if (hit) return hit;

// 2. If visiting root or dashboard while offline, try cached root
const isRootOrDash = !url.search || url.search === '?page=dashboard' || url.search === '?page=landing';
if (isRootOrDash) {
const rootHit = (await cache.match(BASE)) || (await cache.match(req.url.split('?')[0]));
if (rootHit) return rootHit;
}

// 3. For any other page that has not been cached yet, show a clean offline notice rather than trapping on Dashboard
const dashUrl = new URL('./?page=dashboard', self.location).href;
return new Response(`
<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Offline — POS System</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #0a1628;
            color: #f8fafc;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            padding: 20px;
            text-align: center;
            box-sizing: border-box;
        }

        .box {
            background: #112240;
            padding: 36px 24px;
            border-radius: 16px;
            max-width: 440px;
            width: 100%;
            border: 1.5px solid rgba(255, 255, 255, 0.1);
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.5);
        }

        .icon {
            font-size: 3rem;
            margin-bottom: 12px;
        }

        h1 {
            font-size: 1.35rem;
            margin: 0 0 10px;
            color: #38bdf8;
        }

        p {
            color: #94a3b8;
            font-size: 0.92rem;
            line-height: 1.5;
            margin-bottom: 24px;
        }

        .btn {
            display: block;
            width: 100%;
            box-sizing: border-box;
            padding: 12px;
            border-radius: 10px;
            font-weight: 700;
            font-size: .95rem;
            text-decoration: none;
            cursor: pointer;
            margin-bottom: 10px;
            border: none;
        }

        .btn-primary {
            background: #2563eb;
            color: #fff;
        }

        .btn-secondary {
            background: rgba(255, 255, 255, 0.08);
            color: #f8fafc;
            border: 1px solid rgba(255, 255, 255, 0.15);
        }
    </style>
</head>

<body>
    <div class="box">
        <div class="icon">📡</div>
        <h1>Device Offline</h1>
        <p>This page has not been cached on this device yet. Please check your network connection and reload.</p>
        <button class="btn btn-primary" onclick="location.reload()">🔄 Retry Connection</button>
        <a href="${dashUrl}" class="btn btn-secondary">🏠 Back to Dashboard</a>
    </div>
</body>

</html>`, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
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