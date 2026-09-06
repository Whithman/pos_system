@echo off
title POS System - Local Server
cd /d "%~dp0"
echo ============================================
echo   POS SYSTEM - Starting local server...
echo   Browser will open automatically.
echo   Close this window to STOP the server.
echo ============================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-local.ps1"
pause
