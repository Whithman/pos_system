@echo off
title ProCast - Auto Print (Render Online)
cd /d "%~dp0"

set CHROME_PATH=
if exist "C:\Program Files\Google\Chrome\Application\chrome.exe" set CHROME_PATH="C:\Program Files\Google\Chrome\Application\chrome.exe"
if exist "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" set CHROME_PATH="C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set CHROME_PATH="%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"

if "%CHROME_PATH%"=="" (
    echo [ERROR] Google Chrome was not found.
    pause
    exit /b 1
)

:: Start Native Print Agent in background (if not already running)
start "" wscript.exe "%~dp0start-print-agent-silent.vbs"

start "" %CHROME_PATH% --kiosk-printing --user-data-dir="C:\POS-Profile" --app="https://pos-system-9f0n.onrender.com/?page=dashboard"
exit
