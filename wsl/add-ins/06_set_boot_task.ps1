<#
.SYNOPSIS
    Starts a WSL distribution automatically at host boot (no logon required)
.DESCRIPTION
    Registers a SYSTEM scheduled task with an at-startup trigger that instantiates
    the WSL VM as soon as Windows boots. Because it runs as SYSTEM, it needs no
    interactive logon — unlike a per-user task, which only fires after someone
    signs in and therefore cannot recover an unattended machine (e.g. after a
    Windows Update reboot at night).

    This is the generic "WSL is up after a reboot" building block. Keeping a
    distro up once started is a separate concern: an idle distro still stops
    ~80s after its last session closes, and .wslconfig vmIdleTimeout=-1 does NOT
    prevent that (it governs the utility VM, not the distro). Workloads that need
    continuous uptime install an in-guest keepalive as well.
.PARAMETER distroName
    WSL distribution to start at boot (default: "OracleLinux_8_10")
.PARAMETER taskName
    Name of the scheduled task (default: "WSL-Boot-<distroName>")
.PARAMETER remove
    Unregisters the task instead of creating it
.PARAMETER force
    Re-registers the task even when it already exists
.EXAMPLE
    .\06_set_boot_task.ps1 -distroName OracleLinux_8_10
.EXAMPLE
    .\06_set_boot_task.ps1 -remove
.NOTES
    Requires an ELEVATED PowerShell: registering a SYSTEM-principal task is an
    administrative operation.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$distroName = "OracleLinux_8_10",
    [string]$taskName = "",
    [switch]$remove,
    [switch]$force
)

if (-not $taskName) { $taskName = "WSL-Boot-$distroName" }

Write-Host "### 06_set_boot_task.ps1 - Boot task '$taskName' for $distroName" -ForegroundColor Cyan

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

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] WSL not available. Enable the WSL feature and reboot."
    exit 1
}

if ($existing -and -not $force) {
    Write-Host "[OK] '$taskName' already registered (State=$($existing.State)). Use -force to re-register" -ForegroundColor Green
    exit 0
}

try {
    # --exec /bin/true starts the distro and exits immediately: the goal is to
    # instantiate the VM, not to hold a session open.
    $action  = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\wsl.exe" `
                 -Argument "-d $distroName --exec /bin/true"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    # SYSTEM/ServiceAccount is what makes this logon-independent.
    $princ   = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    # StartWhenAvailable catches a missed trigger; no execution time limit so the
    # task is never killed mid-start on a slow boot.
    $set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                 -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)

    if ($PSCmdlet.ShouldProcess($taskName, "register SYSTEM boot task for $distroName")) {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Principal $princ -Settings $set -Force | Out-Null
        Write-Host "- Registered '$taskName' (SYSTEM, at startup)"
        Write-Host "[SUCCESS] $distroName will start automatically at host boot!" -ForegroundColor Green
        Write-Host "  Verify after next reboot: wsl -l -v" -ForegroundColor DarkGray
    }
} catch {
    Write-Error "[ERROR] Boot task registration failed: $_"
    exit 1
}
