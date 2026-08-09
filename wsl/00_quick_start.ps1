<#
.SYNOPSIS
    Quick WSL setup with Oracle Linux distribution
.PARAMETER distroName
    Linux distribution name (default: "OracleLinux_8_10")
.PARAMETER force
    Forces reinstallation of existing components
.PARAMETER bootTask
    Also make the distro survive a host reboot unattended: register a SYSTEM task
    that starts it at boot (06_set_boot_task.ps1, needs elevation) AND install the
    in-guest keepalive that holds it up with no interactive session
    (07_set_keepalive.ps1). Both are needed; neither alone is sufficient.
.NOTES
    DESTRUCTIVE TO RUNNING WORKLOADS: the add-ins invoked below run `wsl --shutdown`
    (01_set_wslconfig.ps1, 01_set_wsl.ps1, 02_set_dns.ps1) to apply configuration.
    That stops the WSL VM and kills anything running inside it, including a
    self-hosted GitHub Actions runner mid-job. Provision before putting the host
    into service, or drain the runner first.
#>
[CmdletBinding()]
param(
    [string]$distroName = "OracleLinux_8_10",
    [switch]$force,
    [switch]$bootTask
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

# Unattended reboot survival. Opt-in: registering a SYSTEM task needs an elevated
# shell, and this is only wanted for machines that must come back on their own.
#
# The two layers are a pair and are applied together — a boot task with no keepalive
# starts the distro and then lets it idle-stop ~80s later, which looks like it worked
# right up until the workload dies.
if ($bootTask) {
    # Starts the distro at host boot (SYSTEM task, no logon).
    & "$scriptDir\add-ins\06_set_boot_task.ps1" -distroName $distroName -force:$force
    # Keeps it running afterwards (in-guest unit, no session).
    & "$scriptDir\add-ins\07_set_keepalive.ps1" -distroName $distroName -force:$force
} else {
    Write-Host "- Skipping reboot survival (pass -bootTask to start $distroName at host boot and keep it up)" -ForegroundColor DarkGray
}

Write-Host "[SUCCESS] WSL setup completed!" -ForegroundColor Green
wsl -l -v