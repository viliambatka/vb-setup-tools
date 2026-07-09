<#
.SYNOPSIS
    Quick setup for WSLg with Oracle Linux distribution
.PARAMETER distroName
    WSL distribution name (default: "OracleLinux_8_10")
.PARAMETER force
    Forces reinstallation
#>
[CmdletBinding()]
param(
    [string]$distroName = "OracleLinux_8_10",
    [switch]$force
)

$WSLgSriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host "### 00_quick_start.ps1 - Setting up WSLg tools on $distroName" -ForegroundColor Cyan
Write-Host " Domain: $domainName | Port: $adminPort | User: $adminUser" -ForegroundColor Yellow

# check WSL  distro is installed
$wslDistros = wsl -l -q | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
if ($distroName -notin $wslDistros) {
    Write-Host "[ERROR] WSL distribution $distroName is not installed. use .\wsl\00_quick_start.ps1"
    Write-Host "Available distributions: $($wslDistros -join ', ')" -ForegroundColor Gray
    exit 1
}

# Install Ansible script convert to WSL path
$wslWSLgSriptDir = (wsl -d $distroName -e wslpath "$WSLgSriptDir").Trim()
$script = @"
set -e
$(if ($force) { "export FORCE_MODE=true" } else { "export FORCE_MODE=false" })
$wslWSLgSriptDir/01_set_wslg.sh
"@
# convert line endings
$script = $script -replace "`r`n", "`n" -replace "`r", "`n"
# executre
wsl -d $distroName -u root -- bash -c "$script"

Write-Host "[SUCCESS] WSLg setup complete!" -ForegroundColor Green
