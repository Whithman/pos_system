@echo off
title ProCast Server Launcher
echo ===================================================
echo Starting ProCast POS System (Apache and MySQL)...
echo ===================================================

cd /D c:\xampp

echo [1/2] Starting MySQL Database...
start "" "mysql\bin\mysqld.exe" --defaults-file=mysql\bin\my.ini --standalone

ping -n 3 127.0.0.1 >nul

echo [2/2] Starting Apache Web Server...
start "" "apache\bin\httpd.exe" -d c:\xampp\apache

ping -n 3 127.0.0.1 >nul

echo.
echo ===================================================
echo ProCast Server is RUNNING!
echo Access the system at: http://localhost/pos_system/
echo ===================================================
ping -n 5 127.0.0.1 >nul

