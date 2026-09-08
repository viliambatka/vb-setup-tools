<#
.SYNOPSIS
    Quick Ansible setup for WSL
.PARAMETER distroName
    WSL distribution name (default: "OracleLinux_9_5")
.PARAMETER force
    Forces Ansible reinstallation
#>
[CmdletBinding()]
param(
    [string]$distroName = "OracleLinux_9_5",
    [switch]$force
)

$ansibleScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host "### 00_quick_start.ps1 - Setting up Ansible on $distroName" -ForegroundColor Cyan
Write-Host " Domain: $domainName | Port: $adminPort | User: $adminUser" -ForegroundColor Yellow

# check WSL  distro is installed
$wslDistros = wsl -l -q | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
if ($distroName -notin $wslDistros) {
    Write-Host "[ERROR] WSL distribution $distroName is not installed. use .\wsl\00_quick_start.ps1"
    Write-Host "Available distributions: $($wslDistros -join ', ')" -ForegroundColor Gray
    exit 1
}

# Install Ansible script convert to WSL path
$wslAnsibleScriptDir = (wsl -d $distroName -e wslpath "$ansibleScriptDir").Trim()
$script = @"
set -e
$(if ($force) { "export FORCE_MODE=true" } else { "export FORCE_MODE=false" })
$wslAnsibleScriptDir/01_set_ansible.sh
"@
# convert line endings
$script = $script -replace "`r`n", "`n" -replace "`r", "`n"
# executre
wsl -d $distroName -u root -- bash -c "$script"

Write-Host "[SUCCESS] Ansible setup complete!" -ForegroundColor Green
Write-Host "- Test: wsl -d $distroName -- ansible --version" -ForegroundColor Yellow
