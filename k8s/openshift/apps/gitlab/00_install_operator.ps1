[CmdletBinding()]
param(
    [string]$InstancePrefix = 'dev',
    [string]$Namespace = 'gitlab-system',
    [string]$OperatorGroupName = 'gitlab-operator-group',
    [string]$SubscriptionName = 'gitlab-operator',
    [string]$PackageName = 'gitlab-operator-kubernetes',
    [string]$Channel = 'stable',
    [string]$Source = 'community-operators',
    [string]$SourceNamespace = 'openshift-marketplace',
    [ValidateSet('Automatic', 'Manual')]
    [string]$InstallPlanApproval = 'Automatic',
    [int]$TimeoutSeconds = 900,
    [switch]$skipWait,
    [switch]$force
)

Write-Host "### k8s/openshift/apps/gitlab/00_install_operator.ps1 - Install GitLab Operator on OpenShift" -ForegroundColor Cyan

if (-not [string]::IsNullOrWhiteSpace($InstancePrefix)) {
    $normalizedInstancePrefix = $InstancePrefix.Trim().ToLowerInvariant()
    if ($normalizedInstancePrefix -notmatch '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$') {
        Write-Host "[ERROR] -InstancePrefix must contain only lowercase letters, numbers, and hyphens, and must start/end with a letter or number." -ForegroundColor Red
        exit 1
    }

    $namespaceSuffix = $normalizedInstancePrefix
    if ($namespaceSuffix -match '^gitlab-(.+)$') {
        $namespaceSuffix = $Matches[1]
    }

    $Namespace = "gitlab-$namespaceSuffix"
}

function Wait-ForOperatorInstall {
    param(
        [string]$TargetNamespace,
        [string]$TargetSubscriptionName,
        [int]$MaxWaitSeconds,
        [bool]$AutoApproveInstallPlans
    )

    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    $csvName = $null
    while ((Get-Date) -lt $deadline -and -not $csvName) {
        if ($AutoApproveInstallPlans) {
            Approve-PendingInstallPlans -TargetNamespace $TargetNamespace
        }

        $subscriptionJson = oc -n $TargetNamespace get subscription $TargetSubscriptionName -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($subscriptionJson | Out-String))) {
            $csvName = ($subscriptionJson | ConvertFrom-Json).status.currentCSV
        }
        if (-not $csvName) { Start-Sleep -Seconds 5 }
    }

    if (-not $csvName) {
        Write-Host "[WARN] Subscription was created, but no current CSV was reported within $MaxWaitSeconds seconds." -ForegroundColor Yellow
        return
    }

    Write-Host "- Waiting for CSV $csvName to reach Succeeded" -ForegroundColor Cyan
    while ((Get-Date) -lt $deadline) {
        if ($AutoApproveInstallPlans) {
            Approve-PendingInstallPlans -TargetNamespace $TargetNamespace
        }

        $csvJson = oc -n $TargetNamespace get csv $csvName -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($csvJson | Out-String))) {
            $phase = ($csvJson | ConvertFrom-Json).status.phase
            if ($phase -eq 'Succeeded') {
                Write-Host "[SUCCESS] CSV $csvName is Succeeded." -ForegroundColor Green
                return
            }
            if ($phase -eq 'Failed') {
                Write-Host "[ERROR] CSV $csvName failed." -ForegroundColor Red
                oc -n $TargetNamespace describe csv $csvName
                exit 1
            }
        }
        Start-Sleep -Seconds 5
    }

    Write-Host "[WARN] Timed out waiting for the GitLab Operator CSV to finish. Check the subscription and install plan manually." -ForegroundColor Yellow
    Show-OperatorDiagnostics -TargetNamespace $TargetNamespace -TargetSubscriptionName $TargetSubscriptionName -CsvName $csvName
}

function Approve-PendingInstallPlans {
    param([string]$TargetNamespace)

    $installPlansJson = oc -n $TargetNamespace get installplan -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($installPlansJson | Out-String))) {
        return
    }

    $installPlans = ($installPlansJson | ConvertFrom-Json).items
    foreach ($installPlan in $installPlans) {
        if ($installPlan.spec.approved -eq $true) {
            continue
        }

        $csvNames = @($installPlan.spec.clusterServiceVersionNames)
        $isGitLabPlan = $false
        foreach ($csvName in $csvNames) {
            if ($csvName -like 'gitlab-operator-kubernetes.*') {
                $isGitLabPlan = $true
                break
            }
        }

        if (-not $isGitLabPlan) {
            continue
        }

        $installPlanName = $installPlan.metadata.name
        Write-Host "- Approving pending InstallPlan $installPlanName" -ForegroundColor Cyan
        & oc -n $TargetNamespace patch installplan $installPlanName --type merge -p '{"spec":{"approved":true}}'
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}

function Show-OperatorDiagnostics {
    param([string]$TargetNamespace, [string]$TargetSubscriptionName, [string]$CsvName)

    Write-Host "- Subscription details" -ForegroundColor Cyan
    & oc -n $TargetNamespace describe subscription $TargetSubscriptionName

    Write-Host "- InstallPlans" -ForegroundColor Cyan
    & oc -n $TargetNamespace get installplan

    if (-not [string]::IsNullOrWhiteSpace($CsvName)) {
        Write-Host "- CSV details" -ForegroundColor Cyan
        & oc -n $TargetNamespace describe csv $CsvName
    }

    Write-Host "- Recent namespace events" -ForegroundColor Cyan
    & oc -n $TargetNamespace get events --sort-by=.lastTimestamp
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

Write-Host "- Ensuring namespace $Namespace exists" -ForegroundColor Cyan
$null = oc get namespace $Namespace 2>$null
if ($LASTEXITCODE -ne 0) {
    oc create namespace $Namespace
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$operatorGroupYaml = @"
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: $OperatorGroupName
  namespace: $Namespace
spec:
  targetNamespaces:
  - $Namespace
"@

$subscriptionYaml = @"
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: $SubscriptionName
  namespace: $Namespace
spec:
  channel: $Channel
  installPlanApproval: $InstallPlanApproval
  name: $PackageName
  source: $Source
  sourceNamespace: $SourceNamespace
"@

Write-Host "- Applying OperatorGroup in namespace $Namespace" -ForegroundColor Cyan
$operatorGroupYaml | & oc apply -f -
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "- Applying Subscription for package $PackageName" -ForegroundColor Cyan
$subscriptionYaml | & oc apply -f -
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "- Current subscription status" -ForegroundColor Cyan
oc -n $Namespace get subscription $SubscriptionName
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($InstallPlanApproval -eq 'Automatic') {
    Approve-PendingInstallPlans -TargetNamespace $Namespace
}

if (-not $skipWait) {
    Wait-ForOperatorInstall -TargetNamespace $Namespace -TargetSubscriptionName $SubscriptionName -MaxWaitSeconds $TimeoutSeconds -AutoApproveInstallPlans ($InstallPlanApproval -eq 'Automatic')

    Write-Host "- Operator deployment state" -ForegroundColor Cyan
    & oc -n $Namespace get deployment gitlab-controller-manager 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] The controller deployment was not found yet. This can happen when install plan approval is manual or the install is still progressing." -ForegroundColor Yellow
    }
}
else {
    Write-Host "[SKIP] Wait for CSV/deployment skipped" -ForegroundColor Cyan
}

if ($InstallPlanApproval -eq 'Manual') {
    Write-Host "[INFO] Manual approval is enabled. Approve the generated InstallPlan before expecting the operator deployment to start." -ForegroundColor Cyan
    Write-Host "       Example: oc -n $Namespace get installplan" -ForegroundColor Gray
}

Write-Host "[SUCCESS] GitLab Operator install resources have been applied to namespace $Namespace." -ForegroundColor Green
