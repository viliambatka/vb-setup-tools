[CmdletBinding()]
param(
    [string]$InstancePrefix = '',
    [string]$Namespace = 'gitlab-system',
    [string]$Name = 'gitlab',
    [string]$Domain = '',
    [string]$ChartVersion = '10.1.2',
    [string]$PostgresHost = '',
    [string]$PostgresPasswordSecret = '',
    [string]$PostgresPasswordKey = 'password',
    [string]$RedisHost = '',
    [string]$RedisAuthSecret = '',
    [string]$RedisAuthKey = 'password',
    [string]$ObjectStorageSecret = '',
    [string]$ObjectStorageKey = 'config',
    [string]$RegistryStorageSecret = '',
    [string]$RegistryStorageKey = 'config',
    [string]$BackupStorageSecret = '',
    [string]$BackupStorageKey = 'config',
    [switch]$InstallLocalDependencies,
    [switch]$SkipLocalDependencies,
    [string]$DependencyStorageClass = '',
    [string]$PostgresStorageSize = '5Gi',
    [string]$ObjectStorageSize = '10Gi',
    [string]$CertManagerVersion = 'v1.21.0',
    [switch]$SkipCertManagerInstall,
    [int]$TimeoutSeconds = 1800,
    [switch]$InstallRunner,
    [switch]$skipWait,
    [switch]$clean,
    [switch]$force
)

Write-Host "### k8s/openshift/apps/gitlab/01_install_instance.ps1 - Install GitLab instance on OpenShift/CRC" -ForegroundColor Cyan

if (-not [string]::IsNullOrWhiteSpace($InstancePrefix)) {
    $normalizedInstancePrefix = $InstancePrefix.Trim().ToLowerInvariant()
    if ($normalizedInstancePrefix -notmatch '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$') {
        Write-Host "[ERROR] -InstancePrefix must contain only lowercase letters, numbers, and hyphens, and must start/end with a letter or number." -ForegroundColor Red
        exit 1
    }

    $hostSuffix = $normalizedInstancePrefix
    if ($hostSuffix -match '^gitlab-(.+)$') {
        $hostSuffix = $Matches[1]
    }

    $Namespace = "gitlab-$hostSuffix"
    $Name = "gitlab-$hostSuffix"
}
else {
    $hostSuffix = ''
}

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

function Get-SemVerMajor {
    param([string]$Version)

    if ($Version -match '^(\d+)\.') {
        return [int]$Matches[1]
    }

    return 0
}

function New-RandomPassword {
    param([int]$Length = 32)

    $bytes = [byte[]]::new($Length)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', 'A').Replace('/', 'B')
}

function Get-SecretStringValue {
    param([string]$TargetNamespace, [string]$SecretName, [string]$Key)

    $encodedValue = oc -n $TargetNamespace get secret $SecretName -o "jsonpath={.data.$Key}" 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($encodedValue | Out-String))) {
        return ''
    }

    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($encodedValue | Out-String).Trim()))
}

function Wait-ForRollout {
    param([string]$TargetNamespace, [string]$ResourceName, [int]$MaxWaitSeconds)

    Write-Host "- Waiting for $ResourceName" -ForegroundColor Cyan
    & oc -n $TargetNamespace rollout status $ResourceName --timeout="$($MaxWaitSeconds)s"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Ensure-CertManager {
    param([string]$Version, [int]$MaxWaitSeconds)

    $null = oc get crd issuers.cert-manager.io 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "- cert-manager CRDs already exist" -ForegroundColor Cyan
        return
    }

    $manifestUrl = "https://github.com/cert-manager/cert-manager/releases/download/$Version/cert-manager.yaml"
    Write-Host "- Installing cert-manager $Version" -ForegroundColor Cyan
    Write-Host "  $manifestUrl" -ForegroundColor Gray
    & oc apply -f $manifestUrl
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $null = oc get crd issuers.cert-manager.io 2>$null
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 5
    }

    $null = oc get crd issuers.cert-manager.io 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Timed out waiting for cert-manager CRDs." -ForegroundColor Red
        exit 1
    }

    Wait-ForRollout -TargetNamespace 'cert-manager' -ResourceName 'deployment/cert-manager' -MaxWaitSeconds $MaxWaitSeconds
    Wait-ForRollout -TargetNamespace 'cert-manager' -ResourceName 'deployment/cert-manager-cainjector' -MaxWaitSeconds $MaxWaitSeconds
    Wait-ForRollout -TargetNamespace 'cert-manager' -ResourceName 'deployment/cert-manager-webhook' -MaxWaitSeconds $MaxWaitSeconds
}

function Remove-GitLabInstanceResources {
    param([string]$TargetNamespace, [string]$TargetName, [int]$MaxWaitSeconds)

    Write-Host "- Cleaning GitLab instance $TargetName in namespace $TargetNamespace" -ForegroundColor Cyan

    & oc -n $TargetNamespace delete gitlab $TargetName --ignore-not-found=true
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $null = oc -n $TargetNamespace get gitlab $TargetName 2>$null
        if ($LASTEXITCODE -ne 0) { break }
        Start-Sleep -Seconds 5
    }

    $null = oc -n $TargetNamespace get gitlab $TargetName 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[WARN] Timed out waiting for GitLab CR deletion. Continuing cleanup of known resources." -ForegroundColor Yellow
    }

    $labelSelectors = @(
        'app.kubernetes.io/instance=gitlab',
        "release=$TargetName"
    )
    foreach ($selector in $labelSelectors) {
        & oc -n $TargetNamespace delete deploy,statefulset,daemonset,job,cronjob,svc,route,ingress,configmap,secret,pvc -l $selector --ignore-not-found=true
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    $namedResources = @(
        'deployment/gitlab-local-postgresql',
        'deployment/gitlab-local-redis',
        'deployment/gitlab-local-minio',
        'service/gitlab-local-postgresql',
        'service/gitlab-local-redis',
        'service/gitlab-local-minio',
        'pvc/gitlab-local-postgresql',
        'pvc/gitlab-local-minio',
        'job/gitlab-local-minio-buckets',
        'configmap/gitlab-local-postgresql-init',
        'secret/gitlab-local-postgresql',
        'secret/gitlab-local-redis',
        'secret/gitlab-local-minio',
        'secret/gitlab-object-storage',
        'secret/gitlab-object-storage-s3cmd',
        'secret/gitlab-registry-storage'
    )

    foreach ($resource in $namedResources) {
        & oc -n $TargetNamespace delete $resource --ignore-not-found=true
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    Write-Host "[SUCCESS] GitLab instance cleanup completed." -ForegroundColor Green
}

function Install-LocalGitLabDependencies {
    param(
        [string]$TargetNamespace,
        [string]$StorageClass,
        [string]$PgStorageSize,
        [string]$MinioStorageSize,
        [int]$MaxWaitSeconds
    )

    $postgresPassword = Get-SecretStringValue -TargetNamespace $TargetNamespace -SecretName 'gitlab-local-postgresql' -Key 'password'
    if ([string]::IsNullOrWhiteSpace($postgresPassword)) { $postgresPassword = New-RandomPassword }

    $redisPassword = Get-SecretStringValue -TargetNamespace $TargetNamespace -SecretName 'gitlab-local-redis' -Key 'password'
    if ([string]::IsNullOrWhiteSpace($redisPassword)) { $redisPassword = New-RandomPassword }

    $minioRootUser = 'gitlab-minio'
    $existingMinioRootUser = Get-SecretStringValue -TargetNamespace $TargetNamespace -SecretName 'gitlab-local-minio' -Key 'rootUser'
    if (-not [string]::IsNullOrWhiteSpace($existingMinioRootUser)) { $minioRootUser = $existingMinioRootUser }

    $minioRootPassword = Get-SecretStringValue -TargetNamespace $TargetNamespace -SecretName 'gitlab-local-minio' -Key 'rootPassword'
    if ([string]::IsNullOrWhiteSpace($minioRootPassword)) { $minioRootPassword = New-RandomPassword }

    $storageClassYaml = ''
    if (-not [string]::IsNullOrWhiteSpace($StorageClass)) {
        $storageClassYaml = "  storageClassName: $StorageClass`n"
    }

    $dependencyYaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-local-postgresql
  namespace: $TargetNamespace
type: Opaque
stringData:
  password: $postgresPassword
---
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-local-redis
  namespace: $TargetNamespace
type: Opaque
stringData:
  password: $redisPassword
---
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-local-minio
  namespace: $TargetNamespace
type: Opaque
stringData:
  rootUser: $minioRootUser
  rootPassword: $minioRootPassword
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: gitlab-local-postgresql-init
  namespace: $TargetNamespace
data:
  01-init.sql: |
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE EXTENSION IF NOT EXISTS btree_gist;
    CREATE EXTENSION IF NOT EXISTS plpgsql;
    CREATE EXTENSION IF NOT EXISTS amcheck;
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitlab-local-postgresql
  namespace: $TargetNamespace
spec:
  accessModes:
  - ReadWriteOnce
$storageClassYaml  resources:
    requests:
      storage: $PgStorageSize
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitlab-local-postgresql
  namespace: $TargetNamespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitlab-local-postgresql
  template:
    metadata:
      labels:
        app: gitlab-local-postgresql
    spec:
      containers:
      - name: postgresql
        image: docker.io/library/postgres:17
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: gitlabhq_production
        - name: POSTGRES_USER
          value: gitlab
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: gitlab-local-postgresql
              key: password
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        - name: init
          mountPath: /docker-entrypoint-initdb.d
        args:
        - -c
        - shared_preload_libraries=pg_stat_statements
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: gitlab-local-postgresql
      - name: init
        configMap:
          name: gitlab-local-postgresql-init
---
apiVersion: v1
kind: Service
metadata:
  name: gitlab-local-postgresql
  namespace: $TargetNamespace
spec:
  selector:
    app: gitlab-local-postgresql
  ports:
  - name: postgresql
    port: 5432
    targetPort: 5432
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitlab-local-redis
  namespace: $TargetNamespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitlab-local-redis
  template:
    metadata:
      labels:
        app: gitlab-local-redis
    spec:
      containers:
      - name: redis
        image: docker.io/library/redis:7-alpine
        ports:
        - containerPort: 6379
        command:
        - sh
        - -c
        - redis-server --appendonly no --save "" --dir /tmp --requirepass "`$(cat /etc/redis-auth/password)"
        volumeMounts:
        - name: auth
          mountPath: /etc/redis-auth
          readOnly: true
      volumes:
      - name: auth
        secret:
          secretName: gitlab-local-redis
---
apiVersion: v1
kind: Service
metadata:
  name: gitlab-local-redis
  namespace: $TargetNamespace
spec:
  selector:
    app: gitlab-local-redis
  ports:
  - name: redis
    port: 6379
    targetPort: 6379
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitlab-local-minio
  namespace: $TargetNamespace
spec:
  accessModes:
  - ReadWriteOnce
$storageClassYaml  resources:
    requests:
      storage: $MinioStorageSize
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitlab-local-minio
  namespace: $TargetNamespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitlab-local-minio
  template:
    metadata:
      labels:
        app: gitlab-local-minio
    spec:
      containers:
      - name: minio
        image: quay.io/minio/minio:latest
        args:
        - server
        - /data
        - --console-address
        - :9001
        ports:
        - containerPort: 9000
        - containerPort: 9001
        env:
        - name: MC_CONFIG_DIR
          value: /tmp/.mc
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: gitlab-local-minio
              key: rootUser
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: gitlab-local-minio
              key: rootPassword
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: gitlab-local-minio
---
apiVersion: v1
kind: Service
metadata:
  name: gitlab-local-minio
  namespace: $TargetNamespace
spec:
  selector:
    app: gitlab-local-minio
  ports:
  - name: api
    port: 9000
    targetPort: 9000
  - name: console
    port: 9001
    targetPort: 9001
"@

    Write-Host "- Applying local PostgreSQL, Redis, and MinIO resources" -ForegroundColor Cyan
    $dependencyYaml | & oc apply -f -
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Wait-ForRollout -TargetNamespace $TargetNamespace -ResourceName 'deployment/gitlab-local-postgresql' -MaxWaitSeconds $MaxWaitSeconds
    Wait-ForRollout -TargetNamespace $TargetNamespace -ResourceName 'deployment/gitlab-local-redis' -MaxWaitSeconds $MaxWaitSeconds
    Wait-ForRollout -TargetNamespace $TargetNamespace -ResourceName 'deployment/gitlab-local-minio' -MaxWaitSeconds $MaxWaitSeconds

    $null = oc -n $TargetNamespace delete job gitlab-local-minio-buckets --ignore-not-found=true

    $bucketJobYaml = @"
apiVersion: batch/v1
kind: Job
metadata:
  name: gitlab-local-minio-buckets
  namespace: $TargetNamespace
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: mc
        image: quay.io/minio/mc:latest
        command:
        - sh
        - -c
        - |
          mc alias set local http://gitlab-local-minio:9000 "`$MINIO_ROOT_USER" "`$MINIO_ROOT_PASSWORD"
          for bucket in git-lfs gitlab-artifacts gitlab-uploads gitlab-packages gitlab-backups tmp registry; do
            mc mb --ignore-existing "local/`$bucket"
          done
        env:
        - name: MC_CONFIG_DIR
          value: /tmp/.mc
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: gitlab-local-minio
              key: rootUser
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: gitlab-local-minio
              key: rootPassword
"@

    Write-Host "- Creating MinIO buckets for GitLab" -ForegroundColor Cyan
    $bucketJobYaml | & oc apply -f -
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & oc -n $TargetNamespace wait --for=condition=complete job/gitlab-local-minio-buckets --timeout="$($MaxWaitSeconds)s"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $objectStoreConfig = @"
provider: AWS
region: us-east-1
aws_access_key_id: $minioRootUser
aws_secret_access_key: $minioRootPassword
endpoint: http://gitlab-local-minio.$TargetNamespace.svc.cluster.local:9000
path_style: true
"@

    $backupConfig = @"
[default]
access_key = $minioRootUser
secret_key = $minioRootPassword
host_base = gitlab-local-minio.$TargetNamespace.svc.cluster.local:9000
host_bucket = gitlab-local-minio.$TargetNamespace.svc.cluster.local:9000
use_https = False
"@

    $registryConfig = @"
s3:
  accesskey: $minioRootUser
  secretkey: $minioRootPassword
  bucket: registry
  region: us-east-1
  regionendpoint: http://gitlab-local-minio.$TargetNamespace.svc.cluster.local:9000
  secure: false
  v4auth: true
  pathstyle: true
"@

    & oc -n $TargetNamespace create secret generic gitlab-object-storage --from-literal=config="$objectStoreConfig" --dry-run=client -o yaml | & oc apply -f -
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & oc -n $TargetNamespace create secret generic gitlab-object-storage-s3cmd --from-literal=config="$backupConfig" --dry-run=client -o yaml | & oc apply -f -
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & oc -n $TargetNamespace create secret generic gitlab-registry-storage --from-literal=config="$registryConfig" --dry-run=client -o yaml | & oc apply -f -
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    return @{
        PostgresHost = "gitlab-local-postgresql.$TargetNamespace.svc.cluster.local"
        PostgresPasswordSecret = 'gitlab-local-postgresql'
        RedisHost = "gitlab-local-redis.$TargetNamespace.svc.cluster.local"
        RedisAuthSecret = 'gitlab-local-redis'
        ObjectStorageSecret = 'gitlab-object-storage'
        RegistryStorageSecret = 'gitlab-registry-storage'
        BackupStorageSecret = 'gitlab-object-storage-s3cmd'
    }
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

Write-Host "- Ensuring namespace $Namespace exists" -ForegroundColor Cyan
$null = oc get namespace $Namespace 2>$null
if ($LASTEXITCODE -ne 0) {
    oc create namespace $Namespace
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$null = oc -n $Namespace get deployment gitlab-controller-manager 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] GitLab Operator deployment was not found in namespace $Namespace." -ForegroundColor Red
    Write-Host "        Run .\k8s\openshift\apps\gitlab\00_install_operator.ps1 -Namespace $Namespace first and approve the InstallPlan if needed." -ForegroundColor Red
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
$hostSuffixYaml = ''
$expectedGitLabHost = "gitlab.$Domain"
if (-not [string]::IsNullOrWhiteSpace($hostSuffix)) {
    $hostSuffixYaml = "          hostSuffix: $hostSuffix`n"
    $expectedGitLabHost = "gitlab-$hostSuffix.$Domain"
}

if ($clean) {
    Remove-GitLabInstanceResources -TargetNamespace $Namespace -TargetName $Name -MaxWaitSeconds $TimeoutSeconds
}

if (-not $SkipCertManagerInstall) {
    Ensure-CertManager -Version $CertManagerVersion -MaxWaitSeconds $TimeoutSeconds
}
else {
    Write-Host "[SKIP] cert-manager install/check skipped" -ForegroundColor Cyan
}

$chartMajor = Get-SemVerMajor -Version $ChartVersion
if ($chartMajor -ge 10) {
    $missingSettingsBeforeLocalInstall = @()
    if ([string]::IsNullOrWhiteSpace($PostgresHost)) { $missingSettingsBeforeLocalInstall += '-PostgresHost' }
    if ([string]::IsNullOrWhiteSpace($PostgresPasswordSecret)) { $missingSettingsBeforeLocalInstall += '-PostgresPasswordSecret' }
    if ([string]::IsNullOrWhiteSpace($RedisHost)) { $missingSettingsBeforeLocalInstall += '-RedisHost' }
    if ([string]::IsNullOrWhiteSpace($RedisAuthSecret)) { $missingSettingsBeforeLocalInstall += '-RedisAuthSecret' }
    if ([string]::IsNullOrWhiteSpace($ObjectStorageSecret)) { $missingSettingsBeforeLocalInstall += '-ObjectStorageSecret' }
    if ([string]::IsNullOrWhiteSpace($RegistryStorageSecret)) { $missingSettingsBeforeLocalInstall += '-RegistryStorageSecret' }
    if ([string]::IsNullOrWhiteSpace($BackupStorageSecret)) { $missingSettingsBeforeLocalInstall += '-BackupStorageSecret' }

    if ($missingSettingsBeforeLocalInstall.Count -gt 0 -and -not $SkipLocalDependencies) {
        $InstallLocalDependencies = $true
    }
}

if ($chartMajor -ge 10 -and $InstallLocalDependencies) {
    $localDependencyOutput = @(Install-LocalGitLabDependencies `
        -TargetNamespace $Namespace `
        -StorageClass $DependencyStorageClass `
        -PgStorageSize $PostgresStorageSize `
        -MinioStorageSize $ObjectStorageSize `
        -MaxWaitSeconds $TimeoutSeconds)
    $localDependencies = $localDependencyOutput[-1]

    if ([string]::IsNullOrWhiteSpace($PostgresHost)) { $PostgresHost = $localDependencies.PostgresHost }
    if ([string]::IsNullOrWhiteSpace($PostgresPasswordSecret)) { $PostgresPasswordSecret = $localDependencies.PostgresPasswordSecret }
    if ([string]::IsNullOrWhiteSpace($RedisHost)) { $RedisHost = $localDependencies.RedisHost }
    if ([string]::IsNullOrWhiteSpace($RedisAuthSecret)) { $RedisAuthSecret = $localDependencies.RedisAuthSecret }
    if ([string]::IsNullOrWhiteSpace($ObjectStorageSecret)) { $ObjectStorageSecret = $localDependencies.ObjectStorageSecret }
    if ([string]::IsNullOrWhiteSpace($RegistryStorageSecret)) { $RegistryStorageSecret = $localDependencies.RegistryStorageSecret }
    if ([string]::IsNullOrWhiteSpace($BackupStorageSecret)) { $BackupStorageSecret = $localDependencies.BackupStorageSecret }
}

if ($chartMajor -ge 10) {
    $missingRequiredSettings = @()
    if ([string]::IsNullOrWhiteSpace($PostgresHost)) { $missingRequiredSettings += '-PostgresHost' }
    if ([string]::IsNullOrWhiteSpace($PostgresPasswordSecret)) { $missingRequiredSettings += '-PostgresPasswordSecret' }
    if ([string]::IsNullOrWhiteSpace($RedisHost)) { $missingRequiredSettings += '-RedisHost' }
    if ([string]::IsNullOrWhiteSpace($RedisAuthSecret)) { $missingRequiredSettings += '-RedisAuthSecret' }
    if ([string]::IsNullOrWhiteSpace($ObjectStorageSecret)) { $missingRequiredSettings += '-ObjectStorageSecret' }
    if ([string]::IsNullOrWhiteSpace($RegistryStorageSecret)) { $missingRequiredSettings += '-RegistryStorageSecret' }
    if ([string]::IsNullOrWhiteSpace($BackupStorageSecret)) { $missingRequiredSettings += '-BackupStorageSecret' }

    if ($missingRequiredSettings.Count -gt 0) {
        Write-Host "[ERROR] GitLab chart $ChartVersion requires external PostgreSQL, Redis, and object storage." -ForegroundColor Red
        Write-Host "        Missing required settings: $($missingRequiredSettings -join ', ')" -ForegroundColor Red
        Write-Host "        Chart 10.0+ removed the bundled PostgreSQL, Redis, and MinIO charts." -ForegroundColor Red
        Write-Host "        Local CRC/dev dependencies are installed by default unless -SkipLocalDependencies is used." -ForegroundColor Red
        Write-Host "        For durable environments, provision managed services and pass the settings above." -ForegroundColor Red
        exit 1
    }
}

$runnerInstall = if ($InstallRunner) { 'true' } else { 'false' }

$externalServicesYaml = ''
$globalExternalServicesYaml = ''
if ($chartMajor -ge 10) {
    $externalServicesYaml = @"
      minio:
        enabled: false
      postgresql:
        install: false
      redis:
        install: false
      registry:
        storage:
          secret: $RegistryStorageSecret
          key: $RegistryStorageKey
          redirect:
            disable: true
      gitlab:
        toolbox:
          backups:
            objectStorage:
              config:
                secret: $BackupStorageSecret
                key: $BackupStorageKey
"@

    $globalExternalServicesYaml = @"
        psql:
          host: $PostgresHost
          password:
            secret: $PostgresPasswordSecret
            key: $PostgresPasswordKey
        redis:
          host: $RedisHost
          auth:
            secret: $RedisAuthSecret
            key: $RedisAuthKey
        appConfig:
          object_store:
            enabled: true
            proxy_download: true
            connection:
              secret: $ObjectStorageSecret
              key: $ObjectStorageKey
"@
}

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
      nginx-ingress:
        enabled: false
      prometheus:
        install: false
      gitlab-runner:
        install: $runnerInstall
$externalServicesYaml
      global:
        hosts:
          domain: $Domain
$hostSuffixYaml
        gatewayApi:
          enabled: false
          configureCertmanager: false
          installEnvoy: false
        ingress:
          enabled: true
          class: none
          configureCertmanager: false
          annotations:
            route.openshift.io/termination: "edge"
$globalExternalServicesYaml
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
Write-Host "[SUCCESS] GitLab instance resources have been applied. Expected URL: https://$expectedGitLabHost" -ForegroundColor Green
