[CmdletBinding()]
param(
    [switch]$cleanup,
	[switch]$force
)

Write-Host "### k8s/k3d/00_quick_start.ps1 - k3d on Windows" -ForegroundColor Cyan

$k3dExe = Join-Path $HOME 'Downloads\k3d-windows-amd64.exe'

function Get-WindowsDockerStatus {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            CliAvailable = $false
            DaemonAvailable = $false
            ErrorMessage = 'Docker CLI is not installed or not on PATH.'
        }
    }

    $dockerInfoOutput = & docker info 2>&1
    if ($LASTEXITCODE -eq 0) {
        return [pscustomobject]@{
            CliAvailable = $true
            DaemonAvailable = $true
            ErrorMessage = $null
        }
    }

    return [pscustomobject]@{
        CliAvailable = $true
        DaemonAvailable = $false
        ErrorMessage = ($dockerInfoOutput | Out-String).Trim()
    }
}

function Get-DockerFailureSummary {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $null
    }

    $lines = $Message -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $preferredLine = $lines | Where-Object { $_ -match 'error|failed|daemon|connect|npipe|pipe|cannot' } | Select-Object -First 1
    if ($preferredLine) {
        return $preferredLine.Trim()
    }

    return ($lines | Select-Object -First 1).Trim()
}

function Ensure-K3dBinary {
    if (Test-Path -Path $k3dExe) {
        return
    }

    Write-Host "- Downloading k3d Windows binary..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://github.com/k3d-io/k3d/releases/download/v5.8.3/k3d-windows-amd64.exe" -OutFile $k3dExe
}

function Test-K3dClusterExists {
    param([string]$Name)

    $clusterList = & $k3dExe cluster list --no-headers 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return ($clusterList | Where-Object { $_ -match "^$([regex]::Escape($Name))(\s|$)" }).Count -gt 0
}

function New-K3dCluster {
    param(
        [string]$Name,
        [string]$Volume,
        [int]$ApiPort,
        [string[]]$ExtraArgs = @()
    )

    if (Test-K3dClusterExists -Name $Name) {
        if ($force) {
            Write-Host "- Recreating existing cluster $Name" -ForegroundColor Yellow
            & $k3dExe cluster delete $Name
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
        else {
            Write-Host "[SKIP] Cluster $Name already exists" -ForegroundColor Cyan
            return
        }
    }

    Write-Host "- Creating cluster $Name" -ForegroundColor Cyan
    & $k3dExe cluster create $Name --volume $Volume --api-port $ApiPort @ExtraArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$dockerStatus = Get-WindowsDockerStatus
if (-not $dockerStatus.DaemonAvailable) {
    if (-not $dockerStatus.CliAvailable) {
        Write-Host "[WARN] Docker CLI is not available on Windows. k3d runs in Windows mode and requires a host Docker installation." -ForegroundColor Yellow
        Write-Host "       Install Docker Desktop or another Windows Docker engine, then rerun .\k8s\k3d\00_quick_start.ps1" -ForegroundColor Yellow
    }
    else {
        Write-Host "[WARN] Docker CLI is installed on Windows, but the Docker engine is not reachable. k3d requires a running host Docker daemon." -ForegroundColor Yellow
        $dockerFailure = Get-DockerFailureSummary -Message $dockerStatus.ErrorMessage
        if (-not [string]::IsNullOrWhiteSpace($dockerFailure)) {
            Write-Host "       Docker reported: $dockerFailure" -ForegroundColor Yellow
        }
        Write-Host "       Start Docker Desktop or fix the active Docker context, then rerun .\k8s\k3d\00_quick_start.ps1" -ForegroundColor Yellow
    }
    exit 0
}

Ensure-K3dBinary

foreach ($path in 'C:\k3d-data1', 'C:\k3d-data2', 'C:\k3d-data3') {
    if (-not (Test-Path -Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

if ($cleanup) {
    foreach ($clusterName in 'cluster1', 'cluster2', 'cluster3') {
        if (Test-K3dClusterExists -Name $clusterName) {
            Write-Host "- Deleting cluster $clusterName" -ForegroundColor Yellow
            & $k3dExe cluster delete $clusterName
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
    }
}

New-K3dCluster -Name 'cluster1' -Volume 'C:\k3d-data1:/var/lib/rancher/k3s/storage' -ApiPort 16443
New-K3dCluster -Name 'cluster2' -Volume 'C:\k3d-data2:/var/lib/rancher/k3s/storage' -ApiPort 16543
New-K3dCluster -Name 'cluster3' -Volume 'C:\k3d-data3:/var/lib/rancher/k3s/storage' -ApiPort 16643 -ExtraArgs @('--servers', '1', '--agents', '3')

docker network ls
docker container ls

if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    kubectl --context k3d-cluster1 get pods -A
    kubectl --context k3d-cluster2 get pods -A
    kubectl --context k3d-cluster3 get pods -A
}
else {
    Write-Host "[WARN] kubectl is not installed on Windows yet; skipping pod checks." -ForegroundColor Yellow
}

Write-Host "[SUCCESS] k3d clusters are configured on Windows." -ForegroundColor Green
