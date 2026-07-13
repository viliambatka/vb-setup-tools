# install gitlab in openshift cluster

Using an OpenShift cluster such as CRC, this folder can install the GitLab Operator through OpenShift OLM.

## install the operator

Run the installer from the repo root or from this folder:

```powershell
.\k8s\openshift\apps\gitlab\00_install_operator.ps1
```

Default behavior:

- installs the operator into namespace `gitlab-system`
- creates an `OperatorGroup` scoped to that namespace
- creates a `Subscription` for package `gitlab-operator-kubernetes`
- uses channel `stable`
- uses `Manual` install plan approval, which is the safer default for OpenShift

## examples

Use automatic approval:

```powershell
.\k8s\openshift\apps\gitlab\00_install_operator.ps1 -InstallPlanApproval Automatic
```

Install into a different namespace:

```powershell
.\k8s\openshift\apps\gitlab\00_install_operator.ps1 -Namespace gitlab-operator
```

Target a non-CRC OpenShift cluster even if local CRC is not running:

```powershell
.\k8s\openshift\apps\gitlab\00_install_operator.ps1 -force
```

## notes

- `oc login` must already be done before running the script.
- If CRC is installed locally, the script checks whether OpenShift is running and warns when it is not.
- GitLab documents OLM-based installation as experimental. For support-sensitive environments, verify that this install path matches your requirements.
- After the subscription is created with manual approval, approve the generated `InstallPlan`:

```powershell
oc -n gitlab-system get installplan
oc -n gitlab-system patch installplan <name> --type merge -p '{"spec":{"approved":true}}'
```

## install a GitLab instance

After the operator deployment is running, apply a GitLab custom resource:

```powershell
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -ChartVersion <compatible-chart-version>
```

The GitLab CR requires `spec.chart.version`. To find the installed operator version and choose a compatible chart version:

```powershell
$csv = oc -n gitlab-system get subscription gitlab-operator -o jsonpath='{.status.currentCSV}'
if ($csv -match 'v?(\d+\.\d+\.\d+)$') { $operatorVersion = $Matches[1] }
"https://gitlab.com/gitlab-org/cloud-native/gitlab-operator/-/blob/$operatorVersion/CHART_VERSIONS"
```

On CRC, the script derives the default domain from the OpenShift console route, for example `apps-crc.testing`, and configures the GitLab chart to use OpenShift Routes:

- disables the bundled NGINX Ingress controller
- disables the bundled Prometheus server because OpenShift already provides metrics
- disables cert-manager integration for GitLab ingress certificates
- disables GitLab Runner by default to reduce CRC resource pressure

Useful options:

```powershell
# pass the CRC/OpenShift apps domain explicitly
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -Domain apps-crc.testing -ChartVersion <compatible-chart-version>

# use a different GitLab CR name
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -Name gitlab-dev -ChartVersion <compatible-chart-version>

# install GitLab Runner as part of the chart
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -ChartVersion <compatible-chart-version> -InstallRunner

# skip the readiness wait loop
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -ChartVersion <compatible-chart-version> -skipWait
```

The chart version must be compatible with the installed GitLab Operator version. If `-ChartVersion` is omitted, the script exits before applying the CR and prints the `CHART_VERSIONS` URL for the installed operator version when it can detect it.

To watch progress:

```powershell
oc -n gitlab-system logs deployment/gitlab-controller-manager -c manager -f
oc -n gitlab-system get gitlab gitlab
oc -n gitlab-system get route
```

GitLab is expected at:

```text
https://gitlab.apps-crc.testing
```

Retrieve the initial root password:

```powershell
$encodedPassword = oc -n gitlab-system get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedPassword))
```
