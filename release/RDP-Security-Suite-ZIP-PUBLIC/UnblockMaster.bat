@echo off
setlocal
cd /d "%~dp0"

echo [UnblockMaster] Step 1/2: Unblocking all files in this package...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0unblock-all-files.ps1"
if errorlevel 1 (
  echo [UnblockMaster] Primary unblock script failed, trying fallback method...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%~dp0' -Recurse -File | Unblock-File"
  if errorlevel 1 (
    echo [UnblockMaster] ERROR: Failed to unblock files.
    echo Run this file as Administrator and try again.
    pause
    exit /b 1
  )
)

if not exist "%~dp0install-clean.ps1" (
  echo [UnblockMaster] ERROR: install-clean.ps1 was not found in this folder.
  pause
  exit /b 1
)

set /p MASTER_CODE=[UnblockMaster] Enter master code: 
if "%MASTER_CODE%"=="" (
  echo [UnblockMaster] ERROR: Master code is required.
  pause
  exit /b 1
)

echo [UnblockMaster] Step 2/2: Starting installer as Administrator...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0install-clean.ps1"" -MasterCode ""%MASTER_CODE%""'"
if errorlevel 1 (
  echo [UnblockMaster] ERROR: Could not start elevated installer.
  pause
  exit /b 1
)

echo [UnblockMaster] Done. Continue in the installer window.
exit /b 0
