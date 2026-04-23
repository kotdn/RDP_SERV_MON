$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Get-ChildItem -Path $root -Recurse -File | Unblock-File
Write-Host 'All files in package were unblocked.'
