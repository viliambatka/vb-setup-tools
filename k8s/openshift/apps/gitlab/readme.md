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
- uses `Automatic` install plan approval

## examples

Use manual approval:

```powershell
.\k8s\openshift\apps\gitlab\00_install_operator.ps1 -InstallPlanApproval Manual
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
- If the subscription is created with manual approval, approve the generated `InstallPlan`:

```powershell
oc -n gitlab-system get installplan
oc -n gitlab-system patch installplan <name> --type merge -p '{"spec":{"approved":true}}'
```

## install a GitLab instance

After the operator deployment is running, install GitLab:

```powershell
.\k8s\openshift\apps\gitlab\01_install_instance.ps1
```

Default behavior:

- uses GitLab chart `10.1.2`
- installs cert-manager when the `issuers.cert-manager.io` CRD is missing
- installs local PostgreSQL, Redis, MinIO, buckets, and storage secrets for CRC/dev
- derives the CRC apps domain from the OpenShift console route
- configures OpenShift Routes instead of the bundled NGINX Ingress controller

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

Useful logs:

```powershell
oc -n gitlab-system logs deployment/gitlab-controller-manager -c manager -f
```

## advanced options

```powershell
# use a different compatible chart version
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -ChartVersion <compatible-chart-version>

# install another instance
# `dev` maps to namespace `gitlab-dev` and URL `https://gitlab-dev.apps-crc.testing`
.\k8s\openshift\apps\gitlab\00_install_operator.ps1 -InstancePrefix dev
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -InstancePrefix dev

# pass the CRC/OpenShift apps domain explicitly
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -Domain apps-crc.testing

# install GitLab Runner as part of the chart
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -InstallRunner

# skip cert-manager installation when it is managed separately
.\k8s\openshift\apps\gitlab\01_install_instance.ps1 -SkipCertManagerInstall
```
