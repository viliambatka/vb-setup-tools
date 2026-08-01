<#
.SYNOPSIS
    Root quick start for VB setup tools.
.PARAMETER All
    Runs all components. This is also the default when no component switches are provided.
.PARAMETER Clean
    Cleans/resets supported components before setup. WSL is not unregistered by this switch.
.PARAMETER Force
    Forces reinstall/recreate behavior for supported components.
.PARAMETER Wsl
    Runs WSL setup.
.PARAMETER Ansible
    Runs Ansible setup.
.PARAMETER WebLogic
    Runs WebLogic setup.
.PARAMETER Docker
    Runs Docker setup.
.PARAMETER K8s
    Runs Kubernetes setup.
.PARAMETER distroName
    WSL distribution name (default: "OracleLinux_8_10").
#>
[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Clean,
    [switch]$Force,
    [switch]$Wsl,
    [switch]$Ansible,
    [switch]$WebLogic,
    [switch]$Docker,
    [switch]$K8s,
    [ValidateSet("Ubuntu-22.04", "OracleLinux_8_10")]
    [string]$distroName = "OracleLinux_8_10"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$componentSelected = $Wsl -or $Ansible -or $WebLogic -or $Docker -or $K8s
$runAll = $All -or -not $componentSelected

Write-Host "### 00_quick_start.ps1 - VB setup tools" -ForegroundColor Cyan
Write-Host "- Distro: $distroName"
Write-Host "- Mode: $(if ($runAll) { 'All' } else { 'Selected' })"
Write-Host "- Clean: $Clean"
Write-Host "- Force: $Force"

if ($Clean) {
    Write-Host "[INFO] -Clean resets supported components only. It does not unregister or delete WSL distributions." -ForegroundColor Yellow
}

if ($runAll -or $Wsl) {
    & "$scriptDir\wsl\00_quick_start.ps1" -distroName $distroName -force:$Force
}

if ($runAll -or $Ansible) {
    & "$scriptDir\ansible\00_quick_start.ps1" -distroName $distroName -force:$Force
}

if ($runAll -or $WebLogic) {
    & "$scriptDir\weblogic\00_quick_start.ps1" -distroName $distroName -force:($Force -or $Clean)
}

if ($runAll -or $Docker) {
    & "$scriptDir\docker\00_quick_start.ps1" -distroName $distroName -force:$Force
}

if ($runAll -or $K8s) {
    & "$scriptDir\k8s\00_quick_start.ps1" -distroName $distroName -cleanup:$Clean -force:$Force
}

Write-Host ""
Write-Host "[SUCCESS] Root quick start completed." -ForegroundColor Green
