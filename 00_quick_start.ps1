<#
.SYNOPSIS
    Quick start for all Windows+WSL infrastructure components, with SELECTABLE steps.
.DESCRIPTION
    Steps (canonical order) — each is one component's own 00_quick_start.ps1:
      wsl       wsl\00_quick_start.ps1       Oracle Linux WSL distro (the one hard prerequisite —
                                              the other steps assume it exists and fail with a
                                              clear message if it's missing, but this script does
                                              not enforce running it first when steps are selected
                                              explicitly; include it yourself if starting fresh)
      ansible   ansible\00_quick_start.ps1   Ansible inside WSL
      weblogic  weblogic\00_quick_start.ps1  WebLogic domain inside WSL
      docker    docker\00_quick_start.ps1    Docker Engine inside WSL
      k8s       k8s\00_quick_start.ps1       Kubernetes prerequisites inside WSL (assumes docker)
.PARAMETER Steps
    Which steps to run, in the order listed above regardless of the order given here (e.g.
    -Steps k8s,wsl still runs wsl first). Default: all five, same as this script's historical
    behavior. One name is the equivalent of an "-Only" selector — there is no separate -Only
    parameter, same convention as vb-ai/ollama/02_train.sh's --steps/--only.
.PARAMETER distroName
    WSL distribution name, passed to every selected step (default: "OracleLinux_9_5").
.PARAMETER force
    Forces reinstallation/recreation, passed to every selected step that accepts it (all five
    currently do).
.PARAMETER domainName
    WebLogic domain name — weblogic step only (default: "test_domain").
.PARAMETER adminUser
    WebLogic admin username — weblogic step only (default: "admin").
.PARAMETER adminPassword
    WebLogic admin password — weblogic step only (default: "testpwd1").
.PARAMETER adminPort
    WebLogic admin port — weblogic step only (default: 7001).
.PARAMETER bootTask
    Also make the distro survive a host reboot unattended — wsl step only. See that step's own
    help for what this actually registers (a boot task + an in-guest keepalive).
.EXAMPLE
    .\00_quick_start.ps1
    Full loop: wsl, ansible, weblogic, docker, k8s — unchanged from this script's original
    unconditional behavior.
.EXAMPLE
    .\00_quick_start.ps1 -Steps docker
    Only docker (assumes wsl is already set up).
.EXAMPLE
    .\00_quick_start.ps1 -Steps docker,k8s -force
    Docker then Kubernetes prerequisites, forcing reinstallation of both.
.EXAMPLE
    .\00_quick_start.ps1 -Steps wsl -distroName OracleLinux_9_5 -bootTask
    Just the WSL distro, with reboot-survival enabled.
.NOTES
    DESTRUCTIVE TO RUNNING WORKLOADS when the wsl step runs: its add-ins call `wsl --shutdown`,
    which kills anything running inside WSL, including a self-hosted GitHub Actions runner
    mid-job. See wsl\00_quick_start.ps1's own .NOTES. Excluding wsl via -Steps does not avoid
    this if another selected step's own script also shuts down WSL — check each step's notes.
#>
[CmdletBinding()]
param(
    [ValidateSet("wsl", "ansible", "weblogic", "docker", "k8s")]
    [string[]]$Steps = @("wsl", "ansible", "weblogic", "docker", "k8s"),
    [string]$distroName = "OracleLinux_9_5",
    [switch]$force,
    [string]$domainName = "test_domain",
    [string]$adminUser = "admin",
    [string]$adminPassword = "testpwd1",
    [int]$adminPort = 7001,
    [switch]$bootTask
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Canonical order: a step name repeated or given out of order in -Steps still runs once, in
# this fixed sequence (wsl first — the dependency every other step assumes), same idea as
# 02_train.sh normalizing --steps against ALL_STEPS rather than running them in the order typed.
$ALL_STEPS = @("wsl", "ansible", "weblogic", "docker", "k8s")
$selected = $ALL_STEPS | Where-Object { $Steps -contains $_ }

Write-Host "### 00_quick_start.ps1 - running step(s): $($selected -join ', ')" -ForegroundColor Cyan

foreach ($step in $selected) {
    switch ($step) {
        "wsl" {
            & "$scriptDir\wsl\00_quick_start.ps1" -distroName $distroName -force:$force -bootTask:$bootTask
        }
        "ansible" {
            & "$scriptDir\ansible\00_quick_start.ps1" -distroName $distroName -force:$force
        }
        "weblogic" {
            & "$scriptDir\weblogic\00_quick_start.ps1" -distroName $distroName -domainName $domainName `
                -adminUser $adminUser -adminPassword $adminPassword -adminPort $adminPort -force:$force
        }
        "docker" {
            & "$scriptDir\docker\00_quick_start.ps1" -distroName $distroName -force:$force
        }
        "k8s" {
            & "$scriptDir\k8s\00_quick_start.ps1" -distroName $distroName -force:$force
        }
    }
}
