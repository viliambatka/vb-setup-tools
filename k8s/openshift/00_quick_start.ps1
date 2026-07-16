[CmdletBinding()]
param(
	[switch]$cleanup,
	[switch]$force,
	[string]$pullSecretFile,
	[ValidateRange(4, 64)]
	[int]$cpus = 16,
	[ValidateRange(10240, 131072)]
	[int]$memoryMB = 64000,
	[ValidateRange(31, 500)]
	[int]$diskGB = 64,
	[switch]$skipSetup,
	[switch]$skipLocalNetworkExpose,
	[string]$lanAlias = 'devlab',
	[ValidateRange(1, 65535)]
	[int]$lanHttpPort = 80,
	[ValidateRange(1, 65535)]
	[int]$lanHttpsPort = 443,
	[ValidateRange(1, 65535)]
	[int]$lanApiPort = 6443,
	[ValidateRange(30, 1800)]
	[int]$openShiftWaitSeconds = 600,
	[switch]$localNetworkOnly
)

function Invoke-Crc {
	param([string[]]$Arguments)
	& crc @Arguments
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Test-IsAdministrator {
	$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
	$principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
	return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LanIPv4Address {
	$config = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
		Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address } |
		Select-Object -First 1

	if ($config) {
		return $config.IPv4Address.IPAddress
	}

	$address = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
		Where-Object {
			$_.IPAddress -notlike '127.*' -and
			$_.IPAddress -notlike '169.254.*' -and
			$_.PrefixOrigin -ne 'WellKnown'
		} |
		Select-Object -First 1 -ExpandProperty IPAddress

	return $address
}

function Enable-LocalNetworkPort {
	param(
		[string]$ListenAddress,
		[int]$ListenPort,
		[int]$ConnectPort,
		[string]$RulePrefix = 'CRC OpenShift Local'
	)

	$ruleName = "$RulePrefix $ListenPort"
	function Ensure-FirewallRule {
		$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
		if (-not $existingRule) {
			$null = New-NetFirewallRule `
				-DisplayName $ruleName `
				-Direction Inbound `
				-Action Allow `
				-Protocol TCP `
				-LocalPort $ListenPort `
				-Profile Private
		}
	}

	$existingProxy = netsh interface portproxy show v4tov4 |
		Select-String -Pattern "^\s*$([regex]::Escape($ListenAddress))\s+$ListenPort\s+127\.0\.0\.1\s+$ConnectPort\s*$"

	if ($existingProxy) {
		Write-Host "[OK] Portproxy already exists: $ListenAddress`:$ListenPort -> 127.0.0.1:$ConnectPort" -ForegroundColor Green
		Ensure-FirewallRule
		return
	}

	$conflictingProxy = netsh interface portproxy show v4tov4 |
		Select-String -Pattern "^\s*(?:$([regex]::Escape($ListenAddress))|0\.0\.0\.0)\s+$ListenPort\s+"
	if ($conflictingProxy) {
		Write-Host "[WARN] Skipping $ListenAddress`:$ListenPort because another portproxy rule already uses that listener." -ForegroundColor Yellow
		Write-Host "       Existing rule: $($conflictingProxy.Line.Trim())" -ForegroundColor Yellow
		return
	}

	$listeners = Get-NetTCPConnection -State Listen -LocalPort $ListenPort -ErrorAction SilentlyContinue |
		Where-Object { $_.LocalAddress -in @($ListenAddress, '0.0.0.0', '::') }
	if ($listeners) {
		$ownerProcesses = $listeners |
			Select-Object -ExpandProperty OwningProcess -Unique |
			ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }
		$owners = $ownerProcesses | ForEach-Object { "$($_.ProcessName)[$($_.Id)]" }

		if ($ownerProcesses -and -not ($ownerProcesses | Where-Object { $_.ProcessName -ne 'crc' })) {
			Write-Host "[OK] CRC is already listening on $ListenAddress`:$ListenPort; ensuring firewall rule." -ForegroundColor Green
			Ensure-FirewallRule
		}
		else {
			Write-Host "[WARN] Skipping $ListenAddress`:$ListenPort because it is already used by $($owners -join ', ')." -ForegroundColor Yellow
		}
		return
	}

	$null = netsh interface portproxy add v4tov4 listenaddress=$ListenAddress listenport=$ListenPort connectaddress=127.0.0.1 connectport=$ConnectPort
	Ensure-FirewallRule
}

function Enable-LocalNetworkAccess {
	param(
		[object[]]$PortMappings,
		[string]$Alias
	)

	$lanAddress = Get-LanIPv4Address
	if ([string]::IsNullOrWhiteSpace($lanAddress)) {
		Write-Host "[WARN] Could not determine this machine's LAN IPv4 address." -ForegroundColor Yellow
		return
	}

	if (Test-IsAdministrator) {
		$ports = $PortMappings | ForEach-Object { "$($_.ListenPort)->$($_.ConnectPort)" }
		Write-Host "- Exposing CRC ports on $lanAddress to the local network: $($ports -join ', ')" -ForegroundColor Cyan
		foreach ($mapping in $PortMappings) {
			Enable-LocalNetworkPort -ListenAddress $lanAddress -ListenPort $mapping.ListenPort -ConnectPort $mapping.ConnectPort
		}
	}
	else {
		Write-Host "[WARN] Local network port publishing needs an elevated PowerShell session." -ForegroundColor Yellow
		$ports = $PortMappings | ForEach-Object { $_.ListenPort }
		Write-Host "       Rerun this script as Administrator to add Windows portproxy and Private firewall rules for ports $($ports -join ', ')." -ForegroundColor Yellow
	}

	Write-Host "- Local network DNS/hosts entries for other machines:" -ForegroundColor Cyan
	Write-Host "  $lanAddress api.crc.testing" -ForegroundColor Gray
	Write-Host "  $lanAddress oauth-openshift.apps-crc.testing" -ForegroundColor Gray
	Write-Host "  $lanAddress console-openshift-console.apps-crc.testing" -ForegroundColor Gray
	Write-Host "  $lanAddress gitlab.apps-crc.testing" -ForegroundColor Gray
	Write-Host "  $lanAddress gitlab-dev.apps-crc.testing" -ForegroundColor Gray
	if (-not [string]::IsNullOrWhiteSpace($Alias)) {
		Write-Host "  $lanAddress $Alias" -ForegroundColor Gray
	}
	Write-Host "       Add a wildcard DNS record for *.apps-crc.testing when possible; hosts files do not support wildcards." -ForegroundColor Yellow
}

function Wait-OpenShiftRunning {
	param([int]$TimeoutSeconds)

	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	do {
		$status = (& crc status 2>$null) | Out-String
		if ($status -match 'OpenShift:\s+Running') {
			Write-Host "[OK] OpenShift is running." -ForegroundColor Green
			return $true
		}

		$currentState = 'not ready'
		if ($status -match 'OpenShift:\s+([^\r\n]+)') {
			$currentState = $Matches[1].Trim()
		}
		Write-Host "- Waiting for OpenShift API ($currentState)" -ForegroundColor Cyan
		Start-Sleep -Seconds 10
	} while ((Get-Date) -lt $deadline)

	Write-Host "[WARN] OpenShift did not report Running within $TimeoutSeconds seconds." -ForegroundColor Yellow
	return $false
}

Write-Host "### k8s/openshift/00_quick_start.ps1 - OpenShift Local on Windows" -ForegroundColor Cyan

$lanPortMappings = @(
	@{ ListenPort = $lanHttpPort; ConnectPort = 80 },
	@{ ListenPort = $lanHttpsPort; ConnectPort = 443 },
	@{ ListenPort = $lanApiPort; ConnectPort = 6443 }
)

if ($localNetworkOnly) {
	Enable-LocalNetworkAccess -PortMappings $lanPortMappings -Alias $lanAlias
	Write-Host "[SUCCESS] Local network publishing configured." -ForegroundColor Green
	exit 0
}

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

$openShiftRunning = Wait-OpenShiftRunning -TimeoutSeconds $openShiftWaitSeconds

if ($openShiftRunning -and (Get-Command oc -ErrorAction SilentlyContinue)) {
	Write-Host "- Checking cluster operators" -ForegroundColor Cyan
	& oc get co

	if ($LASTEXITCODE -ne 0) {
		Write-Host "[WARN] OpenShift started, but 'oc get co' did not complete successfully yet." -ForegroundColor Yellow
	}
}
elseif (-not $openShiftRunning) {
	Write-Host "[WARN] Skipping 'oc get co' because the OpenShift API is not reachable yet." -ForegroundColor Yellow
}

if (-not $skipLocalNetworkExpose) {
	Enable-LocalNetworkAccess -PortMappings $lanPortMappings -Alias $lanAlias
}
else {
	Write-Host "[SKIP] Local network expose skipped" -ForegroundColor Cyan
}

Write-Host "[SUCCESS] OpenShift Local is configured." -ForegroundColor Green


