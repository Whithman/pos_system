# ── Local dev launcher for pos_system ────────────────────────
# Reads .env.local (your private credentials), then starts the app:
#   powershell -ExecutionPolicy Bypass -File start-local.ps1
# Then open http://localhost:8000/index.php

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Test-Path "$PSScriptRoot\.env.local")) {
    Write-Host "ERROR: .env.local not found. Copy the template and fill in your DB credentials." -ForegroundColor Red
    exit 1
}

Get-Content "$PSScriptRoot\.env.local" | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { return }
    $name, $value = $line -split '=', 2
    $value = $value.Trim()
    if ($value -ne '') { [Environment]::SetEnvironmentVariable($name.Trim(), $value, 'Process') }
}

if (-not $env:DATABASE_URL -and -not ($env:DB_HOST -and $env:DB_NAME -and $env:DB_USER)) {
    Write-Host "ERROR: .env.local has no database credentials filled in." -ForegroundColor Red
    Write-Host "Edit .env.local first (set DATABASE_URL or DB_HOST/DB_NAME/DB_USER/DB_PASS)."
    exit 1
}

Write-Host "Starting POS System at http://localhost:8000/index.php ..." -ForegroundColor Green
Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
Start-Process 'http://localhost:8000/index.php'
php -S 127.0.0.1:8000 -t .
