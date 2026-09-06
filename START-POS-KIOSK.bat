@echo off
title POS System - Silent Printing Kiosk Mode
cd /d "%~dp0"
echo ========================================================
echo   POS SYSTEM - Starting in Kiosk / Silent Print Mode
echo ========================================================
echo.

:: Locate Chrome
set CHROME_PATH=
if exist "C:\Program Files\Google\Chrome\Application\chrome.exe" set CHROME_PATH="C:\Program Files\Google\Chrome\Application\chrome.exe"
if exist "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" set CHROME_PATH="C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set CHROME_PATH="%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"

if "%CHROME_PATH%"=="" (
    echo [ERROR] Google Chrome was not found. Please install Chrome or launch your browser with --kiosk-printing.
    pause
    exit /b 1
)

:: Check if XAMPP Apache is running on port 80
set TARGET_URL=http://localhost/pos_system/index.php

powershell -NoProfile -Command "$t = New-Object System.Net.Sockets.TcpClient; try { $t.Connect('127.0.0.1', 80); exit 0 } catch { exit 1 }"
if %ERRORLEVEL% EQU 0 (
    echo [OK] XAMPP Apache detected on port 80.
    set TARGET_URL=http://localhost/pos_system/index.php
) else (
    powershell -NoProfile -Command "$t = New-Object System.Net.Sockets.TcpClient; try { $t.Connect('127.0.0.1', 8000); exit 0 } catch { exit 1 }"
    if %ERRORLEVEL% EQU 0 (
        echo [OK] POS local server detected on port 8000.
        set TARGET_URL=http://localhost:8000/index.php
    ) else (
        echo [INFO] Starting background PHP server on port 8000...
        start /b powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-local.ps1"
        timeout /t 2 /nobreak >nul
        set TARGET_URL=http://localhost:8000/index.php
    )
)

echo [OK] Launching POS with Silent Printing enabled...
start "" %CHROME_PATH% --kiosk-printing --user-data-dir="C:\POS-Profile" --app="%TARGET_URL%"
echo.
echo POS is now running with:
echo  - Silent direct thermal printing (no print preview dialog)
echo  - Automatic cash drawer trigger (via Xprinter XP-58)
echo  - Auto-closing receipt modal
echo.
