param(
    [string]$InstallRoot = "C:\Program Files\RDPSecurityService",
    [switch]$StartMonitor = $false,
    [string]$MasterCode,
    [string]$TelegramBotToken,
    [string]$TelegramChatId,
    [int]$TelegramConfirmTimeoutSec = 180
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

function Invoke-TelegramApi([string]$BotToken, [string]$Method, [hashtable]$Body = @{}) {
    $uri = "https://api.telegram.org/bot$BotToken/$Method"
    return Invoke-RestMethod -Uri $uri -Method Post -Body $Body -TimeoutSec 20
}

function Resolve-TelegramSetting([string]$packageRoot, [string]$botTokenArg, [string]$chatIdArg) {
    $resolvedBotToken = $botTokenArg
    $resolvedChatId = $chatIdArg

    if ([string]::IsNullOrWhiteSpace($resolvedBotToken)) {
        $resolvedBotToken = $env:RDP_TELEGRAM_BOT_TOKEN
    }
    if ([string]::IsNullOrWhiteSpace($resolvedChatId)) {
        $resolvedChatId = $env:RDP_TELEGRAM_CHAT_ID
    }

    $configCandidates = @(
        (Join-Path $packageRoot "config.json"),
        (Join-Path $packageRoot "config.example.json")
    )

    foreach ($configPath in $configCandidates) {
        if (-not (Test-Path $configPath)) {
            continue
        }

        try {
            $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            if ($cfg -and $cfg.telegram) {
                if ([string]::IsNullOrWhiteSpace($resolvedBotToken) -and -not [string]::IsNullOrWhiteSpace($cfg.telegram.botToken)) {
                    $resolvedBotToken = [string]$cfg.telegram.botToken
                }
                if ([string]::IsNullOrWhiteSpace($resolvedChatId) -and -not [string]::IsNullOrWhiteSpace($cfg.telegram.chatId)) {
                    $resolvedChatId = [string]$cfg.telegram.chatId
                }
            }
        } catch {
            Write-Warn "Failed to read Telegram settings from ${configPath}: $($_.Exception.Message)"
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedBotToken)) {
        $resolvedBotToken = Read-Host "Enter Telegram Bot Token for install confirmation"
    }
    if ([string]::IsNullOrWhiteSpace($resolvedChatId)) {
        $resolvedChatId = Read-Host "Enter Telegram Chat ID for install confirmation"
    }

    if ($null -eq $resolvedBotToken) {
        $resolvedBotToken = ""
    }
    if ($null -eq $resolvedChatId) {
        $resolvedChatId = ""
    }

    return @{
        BotToken = $resolvedBotToken.Trim()
        ChatId = $resolvedChatId.Trim()
    }
}

function Wait-TelegramMasterCodeApproval([string]$botToken, [string]$chatId, [int]$timeoutSec) {
    $token = (Get-Random -Minimum 100000 -Maximum 999999).ToString()
    $requestId = [Guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant()
    $hostName = $env:COMPUTERNAME
    $operator = "$env:USERNAME"

    $msg = @(
        "RDP INSTALL CONFIRMATION",
        "Request: $requestId",
        "Host: $hostName",
        "User: $operator",
        "",
        "Reply with command:",
        "/approve $token",
        "",
        "To reject use:",
        "/deny $token"
    ) -join "`n"

    Invoke-TelegramApi -BotToken $botToken -Method "sendMessage" -Body @{
        chat_id = $chatId
        text = $msg
    } | Out-Null

    Write-Step "Telegram confirmation requested (Request: $requestId)."
    Write-Host "Open Telegram and send: /approve $token"

    $offset = 0
    try {
        $bootstrap = Invoke-TelegramApi -BotToken $botToken -Method "getUpdates" -Body @{ timeout = 1 }
        if ($bootstrap.ok -and $bootstrap.result.Count -gt 0) {
            $offset = ([int64]($bootstrap.result | Select-Object -Last 1).update_id) + 1
        }
    } catch {
        Write-Warn "Failed to bootstrap Telegram updates offset: $($_.Exception.Message)"
    }

    $deadline = (Get-Date).AddSeconds([Math]::Max(30, $timeoutSec))
    while ((Get-Date) -lt $deadline) {
        try {
            $updates = Invoke-TelegramApi -BotToken $botToken -Method "getUpdates" -Body @{ offset = $offset; timeout = 10 }
            if (-not $updates.ok -or -not $updates.result) {
                continue
            }

            foreach ($update in $updates.result) {
                $offset = [int64]$update.update_id + 1
                if (-not $update.message) {
                    continue
                }

                $incomingChat = [string]$update.message.chat.id
                if ($incomingChat -ne $chatId) {
                    continue
                }

                $text = ([string]$update.message.text).Trim()
                if ($text -ieq "/approve $token") {
                    return $true
                }

                if ($text -ieq "/deny $token") {
                    throw "Telegram confirmation rejected for request $requestId."
                }
            }
        } catch {
            Write-Warn "Telegram polling error: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds 2
    }

    throw "Telegram confirmation timeout for request $requestId."
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run this script as Administrator."
}

$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$serviceName = "RDPSecurityService"
$serviceExeName = "WinService.exe"
$serviceExeTarget = Join-Path $InstallRoot $serviceExeName
$expectedMasterCode = "RDP-TEST-2026"

if ([string]::IsNullOrWhiteSpace($MasterCode)) {
    $MasterCode = Read-Host "Enter master code"
}

if ($MasterCode -ne $expectedMasterCode) {
    throw "Invalid master code. Installation cancelled."
}

$tg = Resolve-TelegramSetting -packageRoot $packageRoot -botTokenArg $TelegramBotToken -chatIdArg $TelegramChatId
if ([string]::IsNullOrWhiteSpace($tg.BotToken) -or [string]::IsNullOrWhiteSpace($tg.ChatId)) {
    throw "Telegram confirmation is required. Bot token or chat id is empty."
}

Wait-TelegramMasterCodeApproval -botToken $tg.BotToken -chatId $tg.ChatId -timeoutSec $TelegramConfirmTimeoutSec | Out-Null
Write-Ok "Master code confirmed in Telegram."

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