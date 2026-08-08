<#
.SYNOPSIS
    Ensures the user profile .wslconfig contains the required [wsl2] settings
.PARAMETER settings
    Ordered map of [wsl2] keys/values to ensure (default: networkingMode=mirrored, vmIdleTimeout=-1)
.PARAMETER configPath
    Path to .wslconfig (default: "$env:USERPROFILE\.wslconfig")
.PARAMETER memoryRatio
    Fraction of host RAM to give the WSL2 VM (default: 0.5). Set 0 to leave memory unmanaged.
.PARAMETER memoryMaxGB
    Upper bound in GB for the computed memory value (default: 32)
.PARAMETER force
    Restarts WSL even when the file already had the required values
#>
[CmdletBinding()]
param(
    [System.Collections.IDictionary]$settings = [ordered]@{
        networkingMode = 'mirrored'
        vmIdleTimeout  = '-1'
    },
    [string]$configPath = (Join-Path $env:USERPROFILE '.wslconfig'),
    [ValidateRange(0, 1)]
    [double]$memoryRatio = 0.5,
    [ValidateRange(1, 1024)]
    [int]$memoryMaxGB = 32,
    [switch]$force
)

Write-Host "### 01_set_wslconfig.ps1 - Ensuring [wsl2] settings in $configPath" -ForegroundColor Cyan

# Derive memory from this host: min(ratio * host RAM, cap). Skipped if caller passed an explicit memory.
if ($memoryRatio -gt 0 -and -not $settings.Contains('memory')) {
    $hostGB = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    $memGB = [math]::Floor([math]::Min($hostGB * $memoryRatio, $memoryMaxGB))
    if ($memGB -lt 1) { $memGB = 1 }
    Write-Host ("- Host RAM {0:N1} GB -> memory {1}GB (ratio {2}, cap {3}GB)" -f $hostGB, $memGB, $memoryRatio, $memoryMaxGB)
    $settings['memory'] = "${memGB}GB"
}

# Parse the existing file into ordered sections so unrelated settings are preserved
$sections = [ordered]@{}
$current = ''
if (Test-Path -LiteralPath $configPath) {
    foreach ($line in (Get-Content -LiteralPath $configPath)) {
        if ($line -match '^\s*\[(?<name>[^\]]+)\]\s*$') {
            $current = $Matches.name.Trim()
            if (-not $sections.Contains($current)) { $sections[$current] = [ordered]@{} }
            continue
        }
        if ($line -match '^\s*(?<key>[^#;=\s][^=]*?)\s*=\s*(?<value>.*?)\s*$' -and $current) {
            $sections[$current][$Matches.key] = $Matches.value
        }
    }
}

if (-not $sections.Contains('wsl2')) { $sections['wsl2'] = [ordered]@{} }

# Apply required values, tracking whether anything actually changed
$changed = $false
foreach ($key in $settings.Keys) {
    $wanted = [string]$settings[$key]
    $existing = $sections['wsl2'][$key]
    if ($existing -ne $wanted) {
        Write-Host "- Setting [wsl2] $key = $wanted$(if ($null -ne $existing) { " (was: $existing)" })"
        $sections['wsl2'][$key] = $wanted
        $changed = $true
    } else {
        Write-Host "[OK] [wsl2] $key already = $wanted" -ForegroundColor Green
    }
}

if (-not $changed -and -not $force) {
    Write-Host "[OK] .wslconfig already up to date - no changes needed! Use -force to restart WSL anyway" -ForegroundColor Green
    exit 0
}

try {
    if ($changed) {
        # Back up before overwriting an existing config
        if (Test-Path -LiteralPath $configPath) {
            $backupPath = "$configPath.bak"
            Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
            Write-Host "- Backed up previous config to $backupPath"
        }

        $out = foreach ($section in $sections.Keys) {
            "[$section]"
            foreach ($key in $sections[$section].Keys) { "$key=$($sections[$section][$key])" }
            ''
        }
        Set-Content -LiteralPath $configPath -Value $out -Encoding utf8
        Write-Host "- Wrote $configPath"
    }

    # .wslconfig is read only at VM start, so shut down to apply
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        Write-Host "- Shutting down WSL to apply configuration..."
        wsl --shutdown
        Start-Sleep 3
    } else {
        Write-Host "[WARN] WSL not available - settings apply on next WSL start" -ForegroundColor Yellow
    }

    Write-Host "[SUCCESS] .wslconfig configured successfully!" -ForegroundColor Green
} catch {
    Write-Error "[ERROR] .wslconfig configuration failed: $_"
    exit 1
}
