[CmdletBinding()]
param(
    [string]$Namespace = 'gitlab-system',
    [string]$Name = 'gitlab',
    [string]$Domain = '',
    [string]$ChartVersion = '',
    [int]$TimeoutSeconds = 1800,
    [switch]$InstallRunner,
    [switch]$skipWait,
    [switch]$force
)

Write-Host "### k8s/openshift/apps/gitlab/01_install_instance.ps1 - Install GitLab instance on OpenShift/CRC" -ForegroundColor Cyan

function Get-DefaultOpenShiftAppsDomain {
    $consoleHost = oc -n openshift-console get route console -o jsonpath='{.status.ingress[0].host}' 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($consoleHost)) {
        return ''
    }

    $consoleHost = ($consoleHost | Out-String).Trim()
    if ($consoleHost -match '^console-openshift-console\.(.+)$') {
        return $Matches[1]
    }

    return ''
}

function Get-InstalledGitLabOperatorVersion {
    param([string]$TargetNamespace)

    $csvName = ''
    $subscriptionJson = oc -n $TargetNamespace get subscription gitlab-operator -o json 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($subscriptionJson | Out-String))) {
        $csvName = (($subscriptionJson | ConvertFrom-Json).status.currentCSV | Out-String).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($csvName)) {
        $csvNames = oc -n $TargetNamespace get csv -o jsonpath='{.items[*].metadata.name}' 2>$null
        if ($LASTEXITCODE -eq 0) {
            foreach ($candidate in (($csvNames | Out-String).Trim() -split '\s+')) {
                if ($candidate -match 'gitlab-operator') {
                    $csvName = $candidate
                    break
                }
            }
        }
    }

    if ($csvName -match 'v?(\d+\.\d+\.\d+)$') {
        return $Matches[1]
    }

    return ''
}

function Wait-ForGitLabInstance {
    param([string]$TargetNamespace, [string]$TargetName, [int]$MaxWaitSeconds)

    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $gitlabJson = oc -n $TargetNamespace get gitlab $TargetName -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($gitlabJson | Out-String))) {
            $gitlab = $gitlabJson | ConvertFrom-Json
            $status = $gitlab.status.status
            $version = $gitlab.status.version
            if ($status) {
                Write-Host "- GitLab status: $status $version" -ForegroundColor Cyan
            }
            if ($status -in @('Ready', 'Running')) {
                Write-Host "[SUCCESS] GitLab instance $TargetName is $status." -ForegroundColor Green
                return
            }
        }

        Start-Sleep -Seconds 15
    }

    Write-Host "[WARN] Timed out waiting for GitLab to become Ready. Check operator logs and GitLab resources manually." -ForegroundColor Yellow
}

if (-not (Get-Command oc -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] oc is not installed or not on PATH." -ForegroundColor Red
    exit 1
}

$null = oc whoami 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] You are not logged in to an OpenShift cluster. Run 'oc login' first." -ForegroundColor Red
    exit 1
}

if (Get-Command crc -ErrorAction SilentlyContinue) {
    $crcStatus = crc status 2>$null
    if ($LASTEXITCODE -eq 0) {
        if (($crcStatus | Out-String) -notmatch 'OpenShift: +Running' -and -not $force) {
            Write-Host "[WARN] CRC is installed but OpenShift does not appear to be running." -ForegroundColor Yellow
            Write-Host "       Start CRC first or rerun with -force if you are targeting another cluster." -ForegroundColor Yellow
            exit 0
        }
    }
}

$null = oc -n $Namespace get deployment gitlab-controller-manager 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] GitLab Operator deployment was not found in namespace $Namespace." -ForegroundColor Red
    Write-Host "        Run .\k8s\openshift\apps\gitlab\00_install_operator.ps1 first and approve the InstallPlan if needed." -ForegroundColor Red
    exit 1
}

$null = oc get crd gitlabs.apps.gitlab.com 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] GitLab custom resource definition was not found. Wait for the operator install to finish." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = Get-DefaultOpenShiftAppsDomain
}

if ([string]::IsNullOrWhiteSpace($Domain)) {
    Write-Host "[ERROR] Could not determine the OpenShift apps domain automatically." -ForegroundColor Red
    Write-Host "        Pass it explicitly, for example: -Domain apps-crc.testing" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($ChartVersion)) {
    $operatorVersion = Get-InstalledGitLabOperatorVersion -TargetNamespace $Namespace
    Write-Host "[ERROR] No chart version was supplied. The GitLab CR requires spec.chart.version." -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($operatorVersion)) {
        Write-Host "        Installed operator version appears to be $operatorVersion." -ForegroundColor Red
        Write-Host "        Compatible chart versions: https://gitlab.com/gitlab-org/cloud-native/gitlab-operator/-/blob/$operatorVersion/CHART_VERSIONS" -ForegroundColor Red
    }
    else {
        Write-Host "        Get the installed operator CSV with: oc -n $Namespace get subscription gitlab-operator -o jsonpath='{.status.currentCSV}'" -ForegroundColor Red
    }
    Write-Host "        Rerun with: .\k8s\openshift\apps\gitlab\01_install_instance.ps1 -ChartVersion <compatible-chart-version>" -ForegroundColor Red
    exit 1
}

$chartVersionYaml = "    version: `"$ChartVersion`"`n"

$runnerInstall = if ($InstallRunner) { 'true' } else { 'false' }

$gitlabYaml = @"
apiVersion: apps.gitlab.com/v1beta1
kind: GitLab
metadata:
  name: $Name
  namespace: $Namespace
spec:
  chart:
$chartVersionYaml    values:
      installCertmanager: false
      certmanager:
        install: false
      nginx-ingress:
        enabled: false
      prometheus:
        install: false
      gitlab-runner:
        install: $runnerInstall
      global:
        hosts:
          domain: $Domain
        ingress:
          class: none
          configureCertmanager: false
          annotations:
            route.openshift.io/termination: "edge"
"@

Write-Host "- Applying GitLab custom resource $Name in namespace $Namespace" -ForegroundColor Cyan
$gitlabYaml | & oc apply -f -
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "- GitLab custom resource" -ForegroundColor Cyan
oc -n $Namespace get gitlab $Name
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $skipWait) {
    Wait-ForGitLabInstance -TargetNamespace $Namespace -TargetName $Name -MaxWaitSeconds $TimeoutSeconds
}
else {
    Write-Host "[SKIP] Wait for GitLab readiness skipped" -ForegroundColor Cyan
}

Write-Host "- Useful follow-up commands" -ForegroundColor Cyan
Write-Host "  oc -n $Namespace logs deployment/gitlab-controller-manager -c manager -f" -ForegroundColor Gray
Write-Host "  oc -n $Namespace get gitlab $Name" -ForegroundColor Gray
Write-Host "  oc -n $Namespace get route" -ForegroundColor Gray
Write-Host "  `$encodedPassword = oc -n $Namespace get secret $Name-gitlab-initial-root-password -o jsonpath='{.data.password}'" -ForegroundColor Gray
Write-Host "  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(`$encodedPassword))" -ForegroundColor Gray
Write-Host ""
Write-Host "[SUCCESS] GitLab instance resources have been applied. Expected URL: https://gitlab.$Domain" -ForegroundColor Green
