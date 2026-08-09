[CmdletBinding()]
param(
	[switch]$cleanup,
	[switch]$force,
	[switch]$bootTask,
	[string]$pullSecretFile,
	[ValidateRange(4, 64)]
	[int]$cpus = 16,
	[ValidateRange(10240, 131072)]
	[int]$memoryMB = 32000,
	[ValidateRange(31, 500)]
	[int]$diskGB = 64,
	[switch]$skipSetup
)

function Invoke-Crc {
	param([string[]]$Arguments)
	& crc @Arguments
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Write-Host "### k8s/openshift/00_quick_start.ps1 - OpenShift Local on Windows" -ForegroundColor Cyan

if (-not (Get-Command crc -ErrorAction SilentlyContinue)) {
	Write-Host "[ERROR] crc is not installed or not on PATH." -ForegroundColor Red
	Write-Host "        Install OpenShift Local and the OpenShift CLI first:" -ForegroundColor Yellow
	Write-Host "        https://console.redhat.com/openshift/create/local" -ForegroundColor Yellow
	exit 1
}

if (-not (Get-Command oc -ErrorAction SilentlyContinue)) {
	Write-Host "[WARN] oc is not installed or not on PATH. CRC can still start, but cluster checks will be limited." -ForegroundColor Yellow
}


$docker = Get-Command docker -ErrorAction SilentlyContinue
if ($docker) {
	$null = docker version 2>$null
}
if ($LASTEXITCODE -eq 0 -and -not $force) {
	Write-Host "[WARN] Docker is reachable on Windows. Docker Desktop can conflict with CRC because both commonly use port 6443." -ForegroundColor Yellow
	Write-Host "       Stop Docker Desktop first, or rerun with -force if you have already handled the conflict." -ForegroundColor Yellow
	exit 0
}

if ($pullSecretFile) {
	if (-not (Test-Path $pullSecretFile)) {
		Write-Host "[ERROR] Pull secret file not found: $pullSecretFile" -ForegroundColor Red
		exit 1
	}
	$pullSecretFile = (Resolve-Path $pullSecretFile).Path
}
else {
	$pullSecretFile = Get-ChildItem (Join-Path $HOME 'Downloads') -File -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -match 'pull-secret' -and $_.Extension -in '.txt', '.json' } |
		Sort-Object LastWriteTime -Descending |
		Select-Object -First 1 -ExpandProperty FullName
}

if ($cleanup) {
	Write-Host "- Stopping existing CRC instance" -ForegroundColor Yellow
	& crc stop 2>$null

	Write-Host "- Deleting existing CRC instance" -ForegroundColor Yellow
	& crc delete -f 2>$null

	Write-Host "- Cleaning CRC cache and state" -ForegroundColor Yellow
	Invoke-Crc @('cleanup')
}

if (-not $skipSetup) {
	Write-Host "- Running crc setup" -ForegroundColor Cyan
	Invoke-Crc @('setup', '--enable-experimental-features')
}
else {
	Write-Host "[SKIP] crc setup skipped" -ForegroundColor Cyan
}

$startArguments = @('start', '-c', $cpus, '-m', $memoryMB, '-d', $diskGB)

if ($pullSecretFile) {
	Write-Host "- Using pull secret: $pullSecretFile" -ForegroundColor Cyan
	$startArguments += @('--pull-secret-file', $pullSecretFile)
}
else {
	Write-Host "[ERROR] No pull secret file was provided and none was found in $HOME\Downloads." -ForegroundColor Red
	Write-Host "        Download the pull secret from the Red Hat console and rerun with -pullSecretFile <path>." -ForegroundColor Yellow
	exit 1
}

Write-Host "- Starting OpenShift Local with $cpus CPU(s), $memoryMB MB RAM, $diskGB GB disk" -ForegroundColor Cyan
Invoke-Crc $startArguments

Write-Host "- CRC status" -ForegroundColor Cyan
Invoke-Crc @('status')

if (Get-Command oc -ErrorAction SilentlyContinue) {
	Write-Host "- Checking cluster operators" -ForegroundColor Cyan
	& oc get co

	if ($LASTEXITCODE -ne 0) {
		Write-Host "[WARN] OpenShift started, but 'oc get co' did not complete successfully yet." -ForegroundColor Yellow
	}
}

# Optional reboot survival: register a SYSTEM startup task so CRC comes back
# after host reboot without requiring interactive logon.
if ($bootTask) {
	& "$scriptDir\add-ins\06_set_boot_task.ps1" -cpus $cpus -memoryMB $memoryMB -diskGB $diskGB -force:$force
}
else {
	Write-Host "- Skipping reboot survival (pass -bootTask to register CRC startup task)" -ForegroundColor DarkGray
}

Write-Host "[SUCCESS] OpenShift Local is configured." -ForegroundColor Green


