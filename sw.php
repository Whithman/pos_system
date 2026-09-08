<?php
// ═══════════════════════════════════════════════════════════════════════════
// POS SERVICE WORKER — device-side image cache (install once, load fast)
// ═══════════════════════════════════════════════════════════════════════════
header('Content-Type: application/javascript; charset=utf-8');
header('Cache-Control: no-cache');
header('Service-Worker-Allowed: /');

readfile(__DIR__ . '/sw.js');
exit;
