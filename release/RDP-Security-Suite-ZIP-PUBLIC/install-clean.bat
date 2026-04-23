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
set /p MASTER_CODE=Enter master code: 
if "%MASTER_CODE%"=="" (
  echo [ERROR] Master code is required.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install-clean.ps1" -MasterCode "%MASTER_CODE%"
if errorlevel 1 (
  echo [ERROR] Clean install failed.
  pause
  exit /b 1
)

echo [OK] Clean install completed.
pause
exit /b 0