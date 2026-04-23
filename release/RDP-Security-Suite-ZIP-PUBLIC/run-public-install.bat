@echo off
setlocal

echo [1/3] Unblocking files in package folder...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%~dp0' -Recurse -File | Unblock-File"
if errorlevel 1 (
  echo Failed to unblock files. Please run this file as Administrator.
  pause
  exit /b 1
)

echo [2/3] Launching installer with elevation...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0install-clean.ps1""'"
if errorlevel 1 (
  echo Failed to start elevated installer.
  pause
  exit /b 1
)

echo [3/3] Done. Follow installer window.
exit /b 0
