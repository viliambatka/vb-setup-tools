# quick start for kubernetes in windows with wsl2 oracle linux 8


<#
.SYNOPSIS
	Quick start for Kubernetes prerequisites on Windows + WSL2
    note is assumed the docker prerequisites are already install
.DESCRIPTION
	Implements: install Docker Engine inside a WSL distro.
	Placeholders remain for Kubernetes-in-Docker and kubectl installation.
.PARAMETER distroName
	WSL distribution name (default: "OracleLinux_8_10")
.PARAMETER force
	Forces Docker reinstall
#>
[CmdletBinding()]
param(
	[ValidateSet("Ubuntu-22.04", "OracleLinux_8_10")]
	[string]$distroName = "OracleLinux_8_10",
	[switch]$force
)

$k8sScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Split-Path -Parent $k8sScriptDir

Write-Host "### k8s/00_quick_start.ps1 - Kubernetes prereqs on $distroName" -ForegroundColor Cyan

# Check WSL distro is installed
$wslDistros = wsl -l -q | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
if ($distroName -notin $wslDistros) {
	Write-Host "[ERROR] WSL distribution $distroName is not installed. Run .\wsl\00_quick_start.ps1 first." -ForegroundColor Red
	Write-Host "Available distributions: $($wslDistros -join ', ')" -ForegroundColor Gray
	exit 1
}

# Determine default (non-root) user for docker group membership
$wslDefaultUser = (wsl -d $distroName -- whoami 2>$null).Trim()
if ([string]::IsNullOrWhiteSpace($wslDefaultUser)) { $wslDefaultUser = "" }

############################################################
# install docker in WSL
############################################################

# 1) Ensure systemd is enabled (via existing WSL add-in)
try {
	$sysScriptWin = Join-Path $repoRoot 'wsl\add-ins\07_set_system.sh'
	if (Test-Path $sysScriptWin) {
		$sysScriptWsl = (wsl -d $distroName -e wslpath "$sysScriptWin").Trim()
		Write-Host "- Ensuring systemd is enabled in WSL" -ForegroundColor Cyan
		wsl -d $distroName -u root -- bash "$sysScriptWsl"
	} else {
		Write-Host "[WARN] Missing: wsl/add-ins/07_set_system.sh (skipping systemd enable step)" -ForegroundColor Yellow
	}
} catch {
	Write-Host "[WARN] systemd enable step failed: $_" -ForegroundColor Yellow
}

# 2) Run Docker installer inside WSL
try {
	$dockerScriptWin = Join-Path $k8sScriptDir '01_set_docker.sh'
	if (!(Test-Path $dockerScriptWin)) {
		Write-Error "[ERROR] Missing script: $dockerScriptWin"
		exit 1
	}

	$wslDockerScript = (wsl -d $distroName -e wslpath "$dockerScriptWin").Trim()
	$script = @"
set -e
export FORCE_MODE=$(if ($force) { "true" } else { "false" })
export WSL_DOCKER_USER='$wslDefaultUser'
bash '$wslDockerScript'
"@
	$script = $script -replace "`r`n", "`n" -replace "`r", "`n"
	wsl -d $distroName -u root -- bash -c "$script"

	if ($LASTEXITCODE -eq 2) {
		Write-Host "[WARN] Docker install needs a WSL restart for systemd." -ForegroundColor Yellow
		Write-Host "       Run: wsl --shutdown" -ForegroundColor Yellow
		Write-Host "       Then rerun: .\k8s\00_quick_start.ps1" -ForegroundColor Yellow
		exit 2
	} elseif ($LASTEXITCODE -ne 0) {
		throw "Docker installer returned exit code $LASTEXITCODE"
	}
} catch {
	Write-Error "[ERROR] Docker installation failed: $_"
	exit 1
}

# 3) Validate Docker
try {
	Write-Host "- Validating Docker (hello-world)" -ForegroundColor Cyan

	# Validate as root (avoids docker group membership timing issues)
	wsl -d $distroName -u root -- docker version | Out-Null
	if ($LASTEXITCODE -ne 0) { throw "docker version (root) failed" }
	wsl -d $distroName -u root -- docker run --rm hello-world | Out-Null
	if ($LASTEXITCODE -ne 0) { throw "docker hello-world (root) failed" }

	# Optional: validate as default user (may require WSL restart after usermod -aG docker)
	wsl -d $distroName -- docker version 2>$null | Out-Null

	Write-Host "[SUCCESS] Docker Engine is working inside WSL." -ForegroundColor Green
} catch {
	Write-Host "[WARN] Docker installed but validation failed." -ForegroundColor Yellow
	Write-Host "       If you just enabled systemd or added your user to the docker group, run: wsl --shutdown" -ForegroundColor Yellow
	Write-Host "       Then rerun: .\k8s\00_quick_start.ps1" -ForegroundColor Yellow
}

############################################################
# install kubernetes in docker
############################################################
# TODO

############################################################
# install kubectl in WSL
############################################################
# TODO



