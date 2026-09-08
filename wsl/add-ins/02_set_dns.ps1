<#
.SYNOPSIS
    Configures DNS settings for WSL distribution
.PARAMETER distroName
    WSL distribution name (default: "OracleLinux_9_5")
.PARAMETER dnsServers
    DNS servers (auto-detected if not specified)
.PARAMETER force
    Forces DNS reconfiguration
#>
[CmdletBinding()]
param(
    [ValidateSet("OracleLinux_8_10", "OracleLinux_9_5")]
    [string]$distroName = "OracleLinux_9_5",
    [string]$dnsServers = "",
    [switch]$force
)

Write-Host "### 02_set_dns.ps1 - Configuring DNS for $distroName" -ForegroundColor Cyan

# Test DNS function
function Test-DNS($distro) {
    wsl -d $distro --shutdown
    Start-Sleep 2
    wsl -d $distro -- nslookup google.com 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Skip if DNS works (unless forced)
if (-not $force -and (Test-DNS $distroName)) {
    Write-Host "[OK] DNS working - no changes needed! Use -force to reconfigure" -ForegroundColor Green
    exit 0
}

# Auto-detect DNS servers
if (-not $dnsServers) {
    $dnsServers = ((Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -Unique) -join ','
    if (-not $dnsServers) { $dnsServers = '8.8.8.8,1.1.1.1' }
}

try {
    Write-Host "- Setting DNS servers: $dnsServers"
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $wslScriptDir = (wsl -d $distroName -e wslpath "$scriptDir").Trim()
    
    # Configure DNS in WSL
    wsl -d $distroName -u root -- bash "$wslScriptDir/02_set_dns.sh" --dns "$dnsServers"
    
    # Force WSL shutdown to apply wsl.conf changes
    Write-Host "- Restarting WSL to apply configuration..."
    wsl -d $distroName --shutdown
    Start-Sleep 3
    
    # Verify WSL starts and DNS works
    wsl -d $distroName -- echo "WSL restarted" | Out-Null
    Start-Sleep 2
    
    if (Test-DNS $distroName) {
        Write-Host "[SUCCESS] DNS configured successfully!" -ForegroundColor Green
    } else {
        Write-Host "[WARN] DNS setup completed but test failed - try running script again" -ForegroundColor Yellow
    }
} catch {
    Write-Error "[ERROR] DNS configuration failed: $_"
    exit 1
}
