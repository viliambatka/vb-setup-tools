<#
.SYNOPSIS
    Update WSL and install tools
.PARAMETER distroName
    WSL distribution name (default: "OracleLinux_8_10")
.PARAMETER toolList
    Tools to install (default: maven,git,curl,wget,unzip,nano,vim)
.PARAMETER force
    Forces reinstallation
#>
[CmdletBinding()]
param(
    [ValidateSet("Ubuntu-22.04", "OracleLinux_8_10")]
    [string]$distroName = "OracleLinux_8_10",
    [string]$toolList = "maven,git,curl,wget,unzip,nano,vim",
    [switch]$force
)

Write-Host "### 03_set_update.ps1 - Updating $distroName and installing tools" -ForegroundColor Cyan

# Test if tools exist
function Test-Tools($distro, $tools) {
    $missing = @()
    foreach ($tool in $tools) {
        $exists = switch ($tool.ToLower()) {
            "maven" { wsl -d $distro -- mvn --version 2>$null; $LASTEXITCODE -eq 0 }
            "git" { wsl -d $distro -- git --version 2>$null; $LASTEXITCODE -eq 0 }
            default { wsl -d $distro -- which $tool 2>$null; $LASTEXITCODE -eq 0 }
        }
        if (-not $exists) { $missing += $tool }
    }
    return $missing
}

$tools = $toolList -split ',' | ForEach-Object { $_.Trim() }
$missing = Test-Tools $distroName $tools

if (-not $force -and $missing.Count -eq 0) {
    Write-Host "[OK] All tools installed - no updates needed! Use -force to reinstall" -ForegroundColor Green
    exit 0
}


# Enable systemd and cron inside the distro using 07_set_system.sh
try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $sysScriptWin = Join-Path $scriptDir '07_set_system.sh'
    if (-not (Test-Path $sysScriptWin)) {
        $sysScriptWin = Join-Path (Join-Path $scriptDir '.') '07_set_system.sh'
    }
    if (Test-Path $sysScriptWin) {
        $sysScriptWsl = (wsl -d $distroName -e wslpath "$sysScriptWin").Trim()
        Write-Host "- Configuring systemd and cron (07_set_system.sh)" -ForegroundColor Cyan
        wsl -d $distroName -u root -- bash "$sysScriptWsl"
    } else {
        Write-Host "[WARN] 07_set_system.sh not found next to this script; skipping systemd/cron setup" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[WARN] systemd/cron setup failed: $_" -ForegroundColor Yellow
}

# Update and install tools  
try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $sysScriptWin = Join-Path $scriptDir '07_set_system.sh'
    if (-not (Test-Path $sysScriptWin)) {
        $sysScriptWin = Join-Path (Join-Path $scriptDir '.') '07_set_system.sh'
    }
    if (Test-Path $sysScriptWin) {
        $sysScriptWsl = (wsl -d $distroName -e wslpath "$sysScriptWin").Trim()
        Write-Host "- Configuring systemd and cron (07_set_system.sh)" -ForegroundColor Cyan
        wsl -d $distroName -u root -- bash "$sysScriptWsl"
    } else {
        Write-Host "[WARN] 07_set_system.sh not found next to this script; skipping systemd/cron setup" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[WARN] systemd/cron setup failed: $_" -ForegroundColor Yellow
}

# Update and install tools  
try {
    # [string]$toolList = "maven,git,curl,wget,unzip,nano,vim",    
    $isUbuntu = $distroName -match "Ubuntu"
    $installCmd = if ($isUbuntu) { "apt-get install -y" } else { "yum install -y" }
    
    # Map special packages
    $packages = foreach ($tool in $tools) {
        switch ($tool.ToLower()) {
            "nodejs" { if ($isUbuntu) { "nodejs", "npm" } else { "nodejs" } }
            "python3" { "python3", "python3-pip" }
            default { $tool }
        }
    }
    $packageList = ($packages | Select-Object -Unique) -join ' '
    
    Write-Host "- Installing: $packageList"

    wsl -d $distroName -u root -- bash -c "set -e; $installCmd $packageList"

    $stillMissing = Test-Tools $distroName $tools
    if ($stillMissing.Count -eq 0) {
        Write-Host "[SUCCESS] All tools installed successfully!" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Some tools still missing: $($stillMissing -join ', ')" -ForegroundColor Yellow
    }
} catch {
    Write-Error "[ERROR] Installation failed: $_"
    exit 1
}
