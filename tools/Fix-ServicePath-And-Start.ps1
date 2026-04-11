$ErrorActionPreference = "Stop"

$serviceName = "RDPSecurityService"
$exePath = "C:\Users\samoilenkod\source\repos\Winservice\WinService\bin\Release\net8.0\win-x64\WinService.exe"

Write-Host "Configuring service: $serviceName"
Write-Host "Binary path: $exePath"

sc.exe config $serviceName binPath= "`"$exePath`"" start= auto | Out-Host
sc.exe qc $serviceName | Out-Host
sc.exe start $serviceName | Out-Host
Start-Sleep -Seconds 2
sc.exe query $serviceName | Out-Host

Write-Host ""
Write-Host "Tail service.log:"
Get-Content "C:\ProgramData\RDPSecurityService\service.log" -Tail 30 -ErrorAction SilentlyContinue | Out-Host
