<#
.SYNOPSIS
    Sets up WSL with specified Linux distribution
.PARAMETER distroName
    Linux distribution to install (default: "OracleLinux_9_5")
.PARAMETER setdefault
    Sets as default WSL distribution
.PARAMETER force
    Forces reinstallation
#>
[CmdletBinding()]
param (
    [ValidateSet("OracleLinux_8_10", "OracleLinux_9_5")]
    [string]$distroName = "OracleLinux_9_5",
    [switch]$setdefault,
    [switch]$force
)

Write-Host "### 01_set_wsl.ps1 - Setting up WSL with $distroName" -ForegroundColor Cyan

$wslScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Check WSL availability
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] WSL not available. Enable WSL feature and reboot."
    exit 1
}

# Install if missing or forced
$installedDistros = wsl -l -q
if (-not ($installedDistros -contains $distroName) -or $force) {
    Write-Host "- Installing $distroName"
    Write-Host "###################################################################"
    Write-Host "# 1.) When prompted type new Username and new password            #"
    Write-Host "# 2.) then type 'exit' when entering first console to continue    #"
    Write-Host "###################################################################"
    wsl --install -d $distroName
    wsl -d $distroName --shutdown
    Start-Sleep 5
} else {
    Write-Host "[OK] $distroName already installed" -ForegroundColor Green
}

# Set as default
if ($setdefault) {
    wsl --set-default $distroName
    Write-Host "[OK] Set $distroName as default" -ForegroundColor Green
}

wsl -l -v
