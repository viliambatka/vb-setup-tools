# OpenShift

## Prerequisites

- Install OpenShift Local (CRC) and the OpenShift CLI from the official Red Hat page.
- Download your Red Hat pull secret.
- Place the pull-secret file in `$HOME\Downloads` with a name containing `pull-secret`, or pass it explicitly to the script.

[https://console.redhat.com/openshift/create/local](https://console.redhat.com/openshift/create/local)

## Start OpenShift Local on Windows

Run the repository quick-start script instead of calling `crc` manually:

```powershell
.\k8s\openshift\00_quick_start.ps1
```

Useful options:

```powershell
# clean any existing CRC VM and cached state first
.\k8s\openshift\00_quick_start.ps1 -cleanup

# skip `crc setup` if it was already completed earlier
.\k8s\openshift\00_quick_start.ps1 -skipSetup

# pass the pull secret explicitly
.\k8s\openshift\00_quick_start.ps1 -pullSecretFile C:\Users\you\Downloads\pull-secret.txt

# override resource sizing
.\k8s\openshift\00_quick_start.ps1 -cpus 12 -memoryMB 24576 -diskGB 80

# continue even if Docker is reachable on Windows
.\k8s\openshift\00_quick_start.ps1 -force
```

The script:

- checks that `crc` is installed
- warns if Docker Desktop is still running on Windows
- finds the pull secret automatically in `Downloads` when possible
- runs `crc setup`
- starts CRC with the requested CPU, memory, and disk settings
- shows `crc status` and runs `oc get co` when `oc` is available

## Stop and remove CRC

For a full reset, use the same script with cleanup:

```powershell
.\k8s\openshift\00_quick_start.ps1 -cleanup
```

If you only want the native CRC commands:

```powershell
crc stop
crc delete -f
crc cleanup
```

## Install the GitLab Operator

After the cluster is up and you are logged in with `oc login`, use the operator install script:

```powershell
.\k8s\openshift\apps\gitlab\00_install_operator.ps1
```

Useful options:

```powershell
# skip the CSV wait loop
.\k8s\openshift\apps\gitlab\00_install_operator.ps1 -skipWait

# wait longer for operator installation
.\k8s\openshift\apps\gitlab\00_install_operator.ps1 -TimeoutSeconds 1800

# allow targeting a non-CRC cluster even when CRC is installed locally
.\k8s\openshift\apps\gitlab\00_install_operator.ps1 -force

# enable automatic install plan approval
.\k8s\openshift\apps\gitlab\00_install_operator.ps1 -InstallPlanApproval Automatic
```

The script:

- ensures the target namespace exists
- applies the `OperatorGroup`
- applies the `Subscription`
- waits for the CSV to reach `Succeeded` unless `-skipWait` is used
- shows a reminder when manual install-plan approval is enabled

## Install a GitLab instance

After the GitLab Operator deployment is running, apply the GitLab custom resource:

```powershell
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -ChartVersion <compatible-chart-version>
```

The GitLab CR requires a chart version that is compatible with the installed operator version:

```powershell
$csv = oc -n gitlab-system get subscription gitlab-operator -o jsonpath='{.status.currentCSV}'
if ($csv -match 'v?(\d+\.\d+\.\d+)$') { $operatorVersion = $Matches[1] }
"https://gitlab.com/gitlab-org/cloud-native/gitlab-operator/-/blob/$operatorVersion/CHART_VERSIONS"
```

The script:

- derives the CRC apps domain from the OpenShift console route when `-Domain` is not supplied
- configures OpenShift Routes instead of the bundled NGINX Ingress controller
- disables the bundled Prometheus server and GitLab Runner by default for CRC
- exits before applying the CR if `-ChartVersion` is missing
- waits for the GitLab custom resource to become `Ready` or `Running` unless `-skipWait` is used
- prints commands for operator logs, routes, and the initial root password

Useful commands while it reconciles:

```powershell
oc -n gitlab-system logs deployment/gitlab-controller-manager -c manager -f
oc -n gitlab-system get gitlab gitlab
oc -n gitlab-system get route
```

Retrieve the initial root password:

```powershell
$encodedPassword = oc -n gitlab-system get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedPassword))
```

## Notes

- Stop Docker Desktop before starting CRC, unless you intentionally handle the port conflict and run with `-force`.
- `oc` is optional for starting CRC, but required for operator installation and post-start cluster checks.

## Troubleshooting: failed to add user to the group

Hyper-V Administrator group is required to run OpenShift on Windows, if you encounter the error "Failed to add user to the group".

In localized versions of Windows, the group name may be different. For example, in Czech/Slovak Windows, the group name is `Správci technologie Hyper-V`.

```powershell
# open PowerShell as administrator and run one of the following commands
# For English Windows:
Add-LocalGroupMember -Group "Hyper-V Administrators" -Member "$env:USERNAME"

# For Czech/Slovak Windows (or other localized versions):
Add-LocalGroupMember -Group "Správci technologie Hyper-V" -Member "$env:USERNAME"
```
