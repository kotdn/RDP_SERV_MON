param(
    [Parameter(Mandatory = $true)]
    [string]$AttackerIp,

    [int]$DurationSeconds = 60,
    [int]$SampleSeconds = 1,
    [string]$LogsDir = "C:\ProgramData\RDPSecurityService",
    [string]$FirewallRuleName = "RDP_BLOCK_ALL"
)

$ErrorActionPreference = "Stop"

function Get-AttemptsForIp {
    param(
        [string]$Path,
        [string]$Ip
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }

    $pattern = "IP:\s*$([regex]::Escape($Ip))\s*\|\s*Attempts:\s*(\d+)"
    $max = 0

    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $m = [regex]::Match($line, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) {
            $n = [int]$m.Groups[1].Value
            if ($n -gt $max) { $max = $n }
        }
    }

    return $max
}

function Get-LastBlockLineForIp {
    param(
        [string]$Path,
        [string]$Ip
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $pattern = "BLOCKED IP:\s*$([regex]::Escape($Ip))\b"
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match $pattern) {
            return $lines[$i]
        }
    }
    return $null
}

function Test-IpInFirewallRule {
    param(
        [string]$RuleName,
        [string]$Ip
    )

    try {
        $rule = Get-NetFirewallRule -Name $RuleName -ErrorAction Stop
        $addr = $rule | Get-NetFirewallAddressFilter -ErrorAction Stop
        $all = @($addr.RemoteAddress)
        if ($all.Count -eq 0) { return $false }

        foreach ($item in $all) {
            if ($null -eq $item) { continue }
            $v = $item.ToString().Trim()
            if ($v -eq $Ip -or $v -eq "$Ip/32") { return $true }
        }
        return $false
    }
    catch {
        return $false
    }
}

$accessPath = Join-Path $LogsDir "access.log"
$blockPath = Join-Path $LogsDir "block_list.log"
$servicePath = Join-Path $LogsDir "service.log"

Write-Host "=== RDP Security Bruteforce Validator ==="
Write-Host "Attacker IP : $AttackerIp"
Write-Host "Duration    : $DurationSeconds sec"
Write-Host "Sample      : $SampleSeconds sec"
Write-Host "Logs dir    : $LogsDir"
Write-Host ""

$start = Get-Date
$lastAttempts = Get-AttemptsForIp -Path $accessPath -Ip $AttackerIp
$blockedAt = $null

Write-Host ("{0,-20} {1,10} {2,12} {3,14}" -f "Time", "Attempts", "Delta/s", "Banned")
Write-Host ("-" * 60)

while (((Get-Date) - $start).TotalSeconds -lt $DurationSeconds) {
    Start-Sleep -Seconds $SampleSeconds

    $now = Get-Date
    $attempts = Get-AttemptsForIp -Path $accessPath -Ip $AttackerIp
    $delta = $attempts - $lastAttempts
    if ($delta -lt 0) { $delta = 0 }
    $lastAttempts = $attempts

    $isBlockedByLog = $null -ne (Get-LastBlockLineForIp -Path $blockPath -Ip $AttackerIp)
    $isBlockedByFw = Test-IpInFirewallRule -RuleName $FirewallRuleName -Ip $AttackerIp
    $isBlocked = $isBlockedByLog -or $isBlockedByFw

    if ($isBlocked -and -not $blockedAt) {
        $blockedAt = $now
    }

    Write-Host ("{0,-20} {1,10} {2,12} {3,14}" -f $now.ToString("HH:mm:ss"), $attempts, $delta, ($(if ($isBlocked) { "YES" } else { "NO" })))
}

$end = Get-Date
$elapsed = ($end - $start).TotalSeconds
$finalAttempts = Get-AttemptsForIp -Path $accessPath -Ip $AttackerIp
$avgPerSec = 0.0
if ($elapsed -gt 0) {
    $avgPerSec = [Math]::Round(($finalAttempts / $elapsed), 2)
}

$lastBlock = Get-LastBlockLineForIp -Path $blockPath -Ip $AttackerIp
$inFw = Test-IpInFirewallRule -RuleName $FirewallRuleName -Ip $AttackerIp

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "Total attempts seen in access.log : $finalAttempts"
Write-Host "Average attempts/sec (observed)   : $avgPerSec"
Write-Host "Blocked in firewall rule          : $inFw"
if ($blockedAt) {
    $banDelay = [Math]::Round((($blockedAt - $start).TotalSeconds), 2)
    Write-Host "Time to first ban signal          : $banDelay sec"
} else {
    Write-Host "Time to first ban signal          : not reached"
}
if ($lastBlock) {
    Write-Host "Last block_list line              : $lastBlock"
} else {
    Write-Host "Last block_list line              : not found for this IP"
}

if (Test-Path -LiteralPath $servicePath) {
    Write-Host ""
    Write-Host "Recent service.log (tail 15):"
    Get-Content -LiteralPath $servicePath -Tail 15 -Encoding UTF8 | ForEach-Object { Write-Host $_ }
}
