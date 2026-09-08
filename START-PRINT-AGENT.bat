@echo off
title POS Native Print Agent
cd /d "%~dp0"
echo Starting POS Native Print Agent on port 9100...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pos-print-agent.ps1"
pause
