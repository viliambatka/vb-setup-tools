
# Individual components

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

& "$scriptDir\wsl\00_quick_start.ps1"      # WSL only
& "$scriptDir\ansible\00_quick_start.ps1"  # Ansible only
& "$scriptDir\weblogic\00_quick_start.ps1" # WebLogic
& "$scriptDir\docker\00_quick_start.ps1"  # Docker
& "$scriptDir\k8s\00_quick_start.ps1" # Kubernetes
