param(
    [string]$InstallRoot = "C:\Program Files\RDPSecurityService",
    [switch]$StartMonitor = $false
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
}

function Write-Ok([string]$msg) {
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Write-Warn([string]$msg) {
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function New-ShortcutFile([string]$ShortcutPath, [string]$TargetPath, [string]$WorkingDirectory, [string]$Description) {
    $shortcutDir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path $shortcutDir)) {
        New-Item -Path $shortcutDir -ItemType Directory -Force | Out-Null
    }

    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    $shortcut.IconLocation = "$TargetPath,0"
    $shortcut.Save()
}

function Ensure-MonitorShortcuts([string]$InstallRootPath) {
    $monitorExe = Join-Path $InstallRootPath "RDPMonitor.exe"
    if (-not (Test-Path $monitorExe)) {
        Write-Warn "RDPMonitor.exe not found. Shortcuts were not created."
        return
    }

    $publicDesktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDesktopDirectory)
    $programsFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonPrograms)
    $startMenuDir = Join-Path $programsFolder "RDPSecurityService"

    try {
        $desktopShortcut = Join-Path $publicDesktop "RDP Monitor.lnk"
        New-ShortcutFile -ShortcutPath $desktopShortcut -TargetPath $monitorExe -WorkingDirectory $InstallRootPath -Description "RDP Security Monitor"
        Write-Ok "Desktop shortcut created: $desktopShortcut"
    } catch {
        Write-Warn "Failed to create desktop shortcut: $($_.Exception.Message)"
    }

    try {
        $menuShortcut = Join-Path $startMenuDir "RDP Monitor.lnk"
        New-ShortcutFile -ShortcutPath $menuShortcut -TargetPath $monitorExe -WorkingDirectory $InstallRootPath -Description "RDP Security Monitor"
        Write-Ok "Start menu shortcut created: $menuShortcut"
    } catch {
        Write-Warn "Failed to create start menu shortcut: $($_.Exception.Message)"
    }
}

function Stop-ProcessIfRunning([string]$name) {
    try {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($procs) {
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Step "Stopped process: $name"
        }
    } catch {
        Write-Warn "Failed to stop process '$name': $($_.Exception.Message)"
    }
}

function Remove-DirectoryRobust([string]$path) {
    if (-not (Test-Path $path)) {
        return
    }

    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            if (-not (Test-Path $path)) {
                return
            }
        } catch {
            Write-Warn "Remove attempt ${attempt} failed: $($_.Exception.Message)"

            try {
                takeown.exe /F $path /R /D Y | Out-Null
            } catch {
                Write-Warn "takeown failed on attempt ${attempt}: $($_.Exception.Message)"
            }

            try {
                icacls.exe $path /grant "Administrators:(OI)(CI)F" /T /C | Out-Null
            } catch {
                Write-Warn "icacls grant failed on attempt ${attempt}: $($_.Exception.Message)"
            }

            Start-Sleep -Seconds 1
        }
    }

    if (Test-Path $path) {
        throw "Failed to remove install root after retries: $path"
    }
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run this script as Administrator."
}

$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$serviceName = "RDPSecurityService"
$serviceExeName = "WinService.exe"
$serviceExeTarget = Join-Path $InstallRoot $serviceExeName

Write-Step "Package root: $packageRoot"
Write-Step "Target root: $InstallRoot"

# 1) Stop and uninstall existing service
Write-Step "Stopping existing service (if any)..."
try {
    sc.exe stop $serviceName | Out-Null
} catch {
    Write-Warn "Failed to stop service via sc.exe (ignored)."
}

Start-Sleep -Seconds 2

if (Test-Path $serviceExeTarget) {
    Write-Step "Running old service uninstall command..."
    try {
        & $serviceExeTarget uninstall | Out-Null
    } catch {
        Write-Warn "Old service uninstall command failed (ignored)."
    }
}

Write-Step "Deleting existing service registration (if any)..."
try {
    sc.exe delete $serviceName | Out-Null
} catch {
    Write-Warn "Service delete failed (ignored)."
}

Start-Sleep -Seconds 1

# Ensure no old binaries are still loaded before deleting install root.
Stop-ProcessIfRunning -name "WinService"
Stop-ProcessIfRunning -name "RDPMonitor"

# 2) Remove existing install root completely
if (Test-Path $InstallRoot) {
    Write-Step "Removing existing install root..."
    Remove-DirectoryRobust -path $InstallRoot
    Write-Ok "Old install root removed."
}

# 3) Recreate root and copy files
Write-Step "Creating clean install root..."
New-Item -Path $InstallRoot -ItemType Directory -Force | Out-Null

Write-Step "Copying package files to target..."
$exclude = @("install-clean.ps1", "install-clean.bat")
Get-ChildItem -LiteralPath $packageRoot -Force | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $InstallRoot -Recurse -Force
}
Write-Ok "Files copied."

# 4) Install and start service
if (-not (Test-Path $serviceExeTarget)) {
    throw "Service executable not found after copy: $serviceExeTarget"
}

Write-Step "Installing service..."
& $serviceExeTarget install | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "WinService install command failed with exit code $LASTEXITCODE"
}

$installedService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $installedService) {
    throw "Service '$serviceName' was not created. Installation failed."
}

Write-Step "Starting service..."
sc.exe start $serviceName | Out-Host

$startedService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $startedService) {
    throw "Service '$serviceName' disappeared after start command."
}

if ($startedService.Status -ne 'Running') {
    try {
        $startedService.WaitForStatus('Running', (New-TimeSpan -Seconds 20))
        $startedService.Refresh()
    } catch {
    }
}

if ($startedService.Status -ne 'Running') {
    throw "Service '$serviceName' is not running after install/start. Current status: $($startedService.Status)"
}

Write-Ok "Service installed and running."

if ($StartMonitor) {
    $monitorExe = Join-Path $InstallRoot "RDPMonitor.exe"
    if (Test-Path $monitorExe) {
        Write-Step "Starting monitor process..."
        Start-Process -FilePath $monitorExe -WorkingDirectory $InstallRoot | Out-Null
        Write-Ok "Monitor started."
    } else {
        Write-Warn "RDPMonitor.exe not found, monitor was not started."
    }
}

Write-Step "Creating monitor shortcuts..."
Ensure-MonitorShortcuts -InstallRootPath $InstallRoot

Write-Host ""
Write-Ok "Clean installation completed successfully."
Write-Host "Service: $serviceName"
Write-Host "Path: $InstallRoot"