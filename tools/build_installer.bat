@echo off
rem Builds the Windows installer (see build_installer.ps1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_installer.ps1" %*
if errorlevel 1 (
  echo.
  echo Build failed, see the message above.
)
pause
