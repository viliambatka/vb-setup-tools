<#
.SYNOPSIS
    Starts OpenShift Local (CRC) automatically at host boot (no logon required)
.DESCRIPTION
    Registers a SYSTEM scheduled task with an at-startup trigger that executes
    `crc start` using a non-interactive PowerShell command. Because the task runs
    as SYSTEM, it does not depend on a user logon and can recover unattended
    reboots.
.PARAMETER taskName
    Name of the scheduled task (default: "CRC-Boot-Start")
.PARAMETER remove
    Unregisters the task instead of creating it
.PARAMETER force
    Re-registers the task even when it already exists
.EXAMPLE
    .\06_set_boot_task.ps1
.EXAMPLE
    .\06_set_boot_task.ps1 -remove
.NOTES
    Requires an ELEVATED PowerShell: registering a SYSTEM-principal task is an
    administrative operation.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$taskName = "CRC-Boot-Start",
    [ValidateRange(4, 64)]
    [int]$cpus = 16,
    [ValidateRange(10240, 131072)]
    [int]$memoryMB = 48000,
    [ValidateRange(31, 500)]
    [int]$diskGB = 64,
    [switch]$remove,
    [switch]$force
)

Write-Host "### 06_set_boot_task.ps1 - Boot task '$taskName' for CRC" -ForegroundColor Cyan

# Registering a SYSTEM task needs elevation; fail early with a clear message.
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "[ERROR] Must run in an ELEVATED (Administrator) PowerShell. Right-click > Run as administrator."
    exit 1
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

# --- removal path ---
if ($remove) {
    if (-not $existing) {
        Write-Host "[OK] '$taskName' not present - nothing to remove" -ForegroundColor Green
        exit 0
    }
    if ($PSCmdlet.ShouldProcess($taskName, "unregister scheduled task")) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "[SUCCESS] Removed '$taskName'" -ForegroundColor Green
    }
    exit 0
}

if (-not (Get-Command crc -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] CRC is not available on PATH. Install OpenShift Local first."
    exit 1
}

if ($existing -and -not $force) {
    Write-Host "[OK] '$taskName' already registered (State=$($existing.State)). Use -force to re-register" -ForegroundColor Green
    exit 0
}

try {
    # Run `crc start` from cmd.exe so PATH resolution behaves like a normal shell.
    # /c exits after the command completes and does not keep a session around.
    $crcStartArgs = "start -c $cpus -m $memoryMB -d $diskGB"
    $action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\cmd.exe" `
        -Argument "/c crc $crcStartArgs"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    # SYSTEM/ServiceAccount makes startup independent from user logon.
    $princ = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    # StartWhenAvailable catches missed startup trigger opportunities.
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)

    if ($PSCmdlet.ShouldProcess($taskName, "register SYSTEM boot task for CRC")) {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Principal $princ -Settings $set -Force | Out-Null
        Write-Host "- Registered '$taskName' (SYSTEM, at startup)"
        Write-Host "- Startup command: crc $crcStartArgs"
        Write-Host "[SUCCESS] CRC will start automatically at host boot!" -ForegroundColor Green
        Write-Host "  Verify after next reboot: crc status" -ForegroundColor DarkGray
    }
}
catch {
    Write-Error "[ERROR] Boot task registration failed: $_"
    exit 1
}
