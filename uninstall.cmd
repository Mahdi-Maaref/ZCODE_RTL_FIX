@echo off
title ZCode Persian Patch - Uninstall
echo ============================================
echo   ZCode Persian Patch - Uninstall
echo ============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\uninstall.ps1"
echo.
pause
