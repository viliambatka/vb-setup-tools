<#
.SYNOPSIS
    Registers a scheduled task that starts a WSL distribution.
.PARAMETER distroName
    WSL distribution name (default: "OracleLinux_8_10").
.PARAMETER taskName
    Scheduled task name (default: "StartWSL").
.PARAMETER triggerType
    Task trigger type: Startup or Logon.
.PARAMETER RunAsSystem
    Registers the task as SYSTEM. Use with -triggerType Startup only when the distro is available to SYSTEM.
.PARAMETER force
    Replaces an existing task with the same name.
#>
[CmdletBinding()]
param(
    [ValidateSet("Ubuntu-22.04", "OracleLinux_8_10")]
    [string]$distroName = "OracleLinux_8_10",
    [string]$taskName = "StartWSL",
    [ValidateSet("Logon", "Startup")]
    [string]$triggerType = "Startup",
    [switch]$RunAsSystem,
    [switch]$force
)

Write-Host "### 01_set_start_wsl_task.ps1 - Registering WSL start task for $distroName" -ForegroundColor Cyan

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] wsl.exe not available. Enable WSL before registering the task."
    exit 1
}

if ($triggerType -eq "Startup" -and -not (Test-IsAdministrator)) {
    Write-Error "[ERROR] Startup scheduled tasks require an elevated PowerShell session. Run PowerShell as Administrator and try again."
    exit 1
}

$installedDistros = wsl.exe -l -q
if (-not ($installedDistros -contains $distroName)) {
    Write-Error "[ERROR] WSL distribution '$distroName' is not installed."
    wsl.exe -l -v
    exit 1
}

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask -and -not $force) {
    Write-Host "[OK] Scheduled task '$taskName' already exists. Use -force to replace it." -ForegroundColor Green
    exit 0
}

if ($existingTask -and $force) {
    Write-Host "- Removing existing scheduled task '$taskName'"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
}

$wslPath = (Get-Command wsl.exe).Source
$action = New-ScheduledTaskAction `
    -Execute $wslPath `
    -Argument "-d $distroName --exec /bin/sh -lc `"nohup sleep infinity >/dev/null 2>&1 &`""

$trigger = if ($triggerType -eq "Startup") {
    New-ScheduledTaskTrigger -AtStartup
} else {
    New-ScheduledTaskTrigger -AtLogOn
}

if ($RunAsSystem) {
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
} else {
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $currentIdentity -LogonType Interactive -RunLevel Highest
}

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew

try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Start WSL distribution $distroName" `
        -ErrorAction Stop | Out-Null
} catch {
    Write-Error "[ERROR] Failed to register scheduled task '$taskName': $_"
    exit 1
}

Write-Host "[SUCCESS] Scheduled task '$taskName' registered." -ForegroundColor Green
Write-Host "- Trigger: $triggerType"
Write-Host "- Principal: $($principal.UserId)"
Write-Host "- Distro: $distroName"
