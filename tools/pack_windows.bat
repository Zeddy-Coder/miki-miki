@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack_windows.ps1" %*
pause
