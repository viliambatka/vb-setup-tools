<#
.SYNOPSIS
    Quick WSL setup with Oracle Linux distribution
.PARAMETER distroName
    Linux distribution name (default: "OracleLinux_8_10")
.PARAMETER force
    Forces reinstallation of existing components
#>
[CmdletBinding()]
param(
    [string]$distroName = "OracleLinux_8_10",
    [switch]$force
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Write-Host "### 00_quick_start.ps1 - Quick Start WSL with $distroName..." -ForegroundColor Cyan

# Configure user profile .wslconfig ([wsl2] settings)
& "$scriptDir\add-ins\01_set_wslconfig.ps1" -force:$force

# Install WSL distribution
& "$scriptDir\01_set_wsl.ps1" -distroName $distroName -setdefault -force:$force

# Configure DNS
& "$scriptDir\add-ins\02_set_dns.ps1" -distroName $distroName -force:$force

# Install CA certificates
& "$scriptDir\add-ins\04_set_certs.ps1" -distroName $distroName -force:$force

# Update and install tools
& "$scriptDir\add-ins\03_set_update.ps1" -distroName $distroName -force:$force

Write-Host "[SUCCESS] WSL setup completed!" -ForegroundColor Green
wsl -l -v