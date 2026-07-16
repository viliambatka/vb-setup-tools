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

# skip Windows portproxy/firewall setup for local-network access
.\k8s\openshift\00_quick_start.ps1 -skipLocalNetworkExpose

# use a different LAN alias instead of devlab
.\k8s\openshift\00_quick_start.ps1 -lanAlias openshift-lab

# wait longer for OpenShift to become reachable before running oc checks
.\k8s\openshift\00_quick_start.ps1 -openShiftWaitSeconds 900

# only apply LAN portproxy/firewall rules; useful after starting CRC from a non-elevated shell
.\k8s\openshift\00_quick_start.ps1 -localNetworkOnly
```

The script:

- checks that `crc` is installed
- warns if Docker Desktop is still running on Windows
- finds the pull secret automatically in `Downloads` when possible
- runs `crc setup`
- starts CRC with the requested CPU, memory, and disk settings
- waits for OpenShift to report `Running`
- shows `crc status` and runs `oc get co` when `oc` is available
- exposes local-network ports `80`, `443`, and `6443` when run from an elevated PowerShell session

## Execution order

Use this order for a local CRC cluster with GitLab exposed on the LAN:

```powershell
# 1. Start CRC
.\k8s\openshift\00_quick_start.ps1

# 2. If CRC was started from a non-elevated shell, expose it to the LAN from Administrator PowerShell
.\k8s\openshift\00_quick_start.ps1 -localNetworkOnly

# 3. Install the GitLab Operator
.\k8s\openshift\apps\gitlab\00_install_operator.ps1

# 4. Install the GitLab instance
.\k8s\openshift\apps\gitlab\01_install_instance.ps1
```

## Local network access

By default, the quick-start script makes CRC easier to reach from other machines on the same private network:

- CRC keeps its default route ports.
- Windows `portproxy` entries expose `80`, `443`, and `6443` on the Windows host LAN IP and forward them to the CRC host ports.
- Existing listeners or conflicting portproxy rules are reported and skipped instead of being overwritten.
- Windows Firewall Private-profile inbound rules are created for those ports.
- The script prints DNS/hosts entries for `api.crc.testing`, common CRC routes, GitLab routes, and the `devlab` alias.

Run PowerShell as Administrator for the portproxy and firewall changes to be applied. Without elevation, CRC still starts, but the script only prints the DNS/hosts entries.

If CRC is already running and the first run was not elevated, open PowerShell as Administrator and run:

```powershell
.\k8s\openshift\00_quick_start.ps1 -localNetworkOnly
```

For another local-network client, point these names at the Windows host LAN IP printed by the script:

```text
<windows-lan-ip> api.crc.testing
<windows-lan-ip> console-openshift-console.apps-crc.testing
<windows-lan-ip> oauth-openshift.apps-crc.testing
<windows-lan-ip> gitlab.apps-crc.testing
<windows-lan-ip> gitlab-dev.apps-crc.testing
<windows-lan-ip> devlab
```

Prefer a real DNS wildcard record for `*.apps-crc.testing` when possible. Hosts files do not support wildcard names.

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

# require manual install plan approval
.\k8s\openshift\apps\gitlab\00_install_operator.ps1 -InstallPlanApproval Manual
```

The script:

- ensures the target namespace exists
- applies the `OperatorGroup`
- applies the `Subscription`
- waits for the CSV to reach `Succeeded` unless `-skipWait` is used
- shows a reminder when manual install-plan approval is enabled

## Install a GitLab instance

After the GitLab Operator deployment is running, install GitLab:

```powershell
.\k8s\openshift\apps\gitlab\01_install_instance.ps1
```

Default behavior:

- uses GitLab chart `10.1.2`
- installs cert-manager when the `issuers.cert-manager.io` CRD is missing
- installs local PostgreSQL, Redis, MinIO, buckets, and storage secrets for CRC/dev
- creates OpenShift Routes for GitLab, registry, and KAS

Check status:

```powershell
oc -n gitlab-system get gitlab gitlab
oc -n gitlab-system get deploy,statefulset,job,route
```

Open GitLab:

```text
https://gitlab.apps-crc.testing
```

Admin login:

```text
root
```

Get the initial root password:

```powershell
$encodedPassword = oc -n gitlab-system get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedPassword))
```

Clean and reinstall:

```powershell
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -clean
```

Install another instance:

```powershell
# `dev` maps to namespace `gitlab-dev` and URL `https://gitlab-dev.apps-crc.testing`
.\k8s\openshift\apps\gitlab\00_install_operator.ps1 -InstancePrefix dev
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -InstancePrefix dev
```

Useful logs:

```powershell
oc -n gitlab-system logs deployment/gitlab-controller-manager -c manager -f
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
