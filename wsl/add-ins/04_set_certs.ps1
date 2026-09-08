<#
.SYNOPSIS
    Exports Windows CA certificates and configures WSL to use them
.PARAMETER distroName
    WSL Linux distribution name (default: "OracleLinux_9_5")
.PARAMETER exportPath
    Path to export certificates (default: artifacts/windows-ca-certificates_timestamp.crt)
.PARAMETER rootOnly
    Export only root certificates (skip intermediate)
.PARAMETER force
    Forces certificate export and installation even if package manager is working
#>

[CmdletBinding()]
param(
    [string]$distroName = "OracleLinux_9_5",
    [string]$exportPath = "",
    [switch]$rootOnly,
    [switch]$force
)

Write-Host "### 04_set_certs.ps1 - Configuring WSL CA certificates for: $distroName" -ForegroundColor Cyan

# Set default export path
if ([string]::IsNullOrEmpty($exportPath)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $artifactsDir = Join-Path $scriptDir "artifacts"
    if (-not (Test-Path $artifactsDir)) { New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null }
    $exportPath = Join-Path $artifactsDir "windows-ca-certificates_$(Get-Date -Format 'yyyyMMdd_HHmmss').crt"
}

# Check if WSL distribution exists
$wslDistros = wsl -l -q
if ($wslDistros -notcontains $distroName) {
    Write-Error "WSL distribution '$distroName' not found. Available: $($wslDistros -join ', ')"
    exit 1
}

# Test package manager first (unless forced)
if (-not $force) {
    Write-Host "- Testing package manager..."
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $testScript = (wsl -d $distroName -e wslpath "$(Join-Path $scriptDir '06_test_pkg.sh')").Trim()
    wsl -d $distroName -u root -- bash "$testScript" -d "Testing package manager" 2>$null | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Package manager working - no certificate installation needed! Use -force to install anyway" -ForegroundColor Green
        exit 0
    }
    Write-Host "[ERROR] Package manager failing - installing certificates..." -ForegroundColor Yellow

}

try {
    # Export certificates from Windows stores
    Write-Host "- Exporting certificates..." -ForegroundColor Yellow
    $allCerts = @()
    $allCerts += Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.HasPrivateKey -eq $false -and $_.NotAfter -gt (Get-Date) }
    $allCerts += Get-ChildItem Cert:\CurrentUser\Root -ErrorAction SilentlyContinue | Where-Object { $_.HasPrivateKey -eq $false -and $_.NotAfter -gt (Get-Date) }
    
    if (-not $rootOnly) {
        $allCerts += Get-ChildItem Cert:\LocalMachine\CA -ErrorAction SilentlyContinue | Where-Object { $_.HasPrivateKey -eq $false -and $_.NotAfter -gt (Get-Date) }
        $allCerts += Get-ChildItem Cert:\LocalMachine\AuthRoot -ErrorAction SilentlyContinue | Where-Object { $_.HasPrivateKey -eq $false -and $_.NotAfter -gt (Get-Date) }
    }
    
    # Create PEM content
    $uniqueCerts = $allCerts | Sort-Object Thumbprint | Get-Unique -AsString
    $pemContent = @("# Windows CA Export - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "")
    
    foreach ($cert in $uniqueCerts) {
        $subject = ($cert.Subject -replace "`n", " " -replace "`r", "" -replace '"', "'")
        $pemContent += @(
            "# Subject: $subject",
            "-----BEGIN CERTIFICATE-----",
            [System.Convert]::ToBase64String($cert.RawData, [System.Base64FormattingOptions]::InsertLineBreaks),
            "-----END CERTIFICATE-----",
            ""
        )
    }
    
    # Write and install certificates
    $pemContent | Out-File -FilePath $exportPath -Encoding utf8
    Write-Host "[SUCCESS] Exported $($uniqueCerts.Count) certificates" -ForegroundColor Green
    
    # Install certificates directly from current location
    $wslExportPath = (wsl -d $distroName -e wslpath "$exportPath").Trim()
    $bashScript = (wsl -d $distroName -e wslpath "$(Join-Path $scriptDir '04_set_certs.sh')").Trim()
    wsl -d $distroName -u root -- bash "$bashScript" "$wslExportPath"
} catch {
    Write-Error "[ERROR] Configuration failed: $_"
    exit 1
}
