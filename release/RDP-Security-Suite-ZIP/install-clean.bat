@echo off
setlocal

:: Must be run as Administrator
net session >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Please run as Administrator.
  pause
  exit /b 1
)

set SCRIPT_DIR=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install-clean.ps1"
if errorlevel 1 (
  echo [ERROR] Clean install failed.
  pause
  exit /b 1
)

echo [OK] Clean install completed.
pause
exit /b 0