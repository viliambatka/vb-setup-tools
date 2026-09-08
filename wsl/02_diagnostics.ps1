<#
.SYNOPSIS
    Read-only WSL / mirrored-networking diagnostics. Runs a fixed set of host and
    in-guest checks, prints [OK] / [FAIL] / [WARN] per check, and exits non-zero
    if any check FAILed.

.DESCRIPTION
    This script exists because of a concrete failure seen during setup of
    OracleLinux_9_5 on this class of machine:

      - mirrored networking (`networkingMode=mirrored` in .wslconfig) came up with
        NO connectivity: every `eth*` DOWN, empty routing table, and the guest
        kernel log spamming:
            hv_netvsc <GUID> ... unable to open channel: -19   (-ENODEV)
            hv_vmbus:  probe failed for device <GUID> (-19)
      - one specific netvsc VMBus channel was being OFFERED to the guest by the
        Windows host but could not be BACKED (no ring buffer / GPADL), so the
        whole mirrored bring-up stalled waiting for it.
      - `wsl --shutdown` did NOT clear it (that only recycles the utility VM, not
        the host-side HNS / vmcompute / vmbus.sys state that holds the stale
        channel). Only a full Windows REBOOT restored a working state, with the
        primary uplink coming up on the LAN.

    IMPORTANT NUANCE learned from running this script on a HEALTHY machine:
    the `-ENODEV` netvsc error is NOT by itself a failure. Mirrored mode mirrors
    EVERY host adapter (incl. WAN Miniports and disconnected Wi-Fi virtuals), and
    there is normally ONE such device that cannot be backed and logs -19 forever.
    The other mirrored NICs still come up and you get a default route on the LAN.
    The failure case is: `-ENODEV` present AND no default route (the un-backable
    channel landed on the device that was meant to be the uplink, and nothing
    else covered it). So this script FAILs only on that combination; a lone
    `-ENODEV` with a working default route is a WARN.

    None of the setup scripts (00_quick_start.ps1 and add-ins) can recover from
    that state - they only ever call `wsl --shutdown`. So when mirrored mode is
    dead, you need evidence to decide between "bounce HNS/vmcompute" and "reboot
    Windows", and that evidence is destroyed by the reboot. Run this BEFORE
    rebooting to capture it.

    The script is READ-ONLY. It changes nothing: no .wslconfig edits, no
    `wsl --shutdown`, no service restarts, no adapter toggles.

.PARAMETER distroName
    Distribution to probe in-guest (default: OracleLinux_9_5). If it is not
    installed the guest checks are reported as SKIP, not FAIL.

.PARAMETER SkipGuest
    Only run host-side checks (use when no distro is installed yet).

.PARAMETER TranscriptPath
    If set, a full PowerShell transcript (every raw command output) is written
    here as well as the pass/fail summary on screen. Useful to attach to a bug
    report.

.EXAMPLE
    .\02_diagnostics.ps1
    .\02_diagnostics.ps1 -SkipGuest
    .\02_diagnostics.ps1 -TranscriptPath .\wsl-diag.txt
#>
[CmdletBinding()]
param(
    [ValidateSet("OracleLinux_8_10", "OracleLinux_9_5")]
    [string]$distroName = "OracleLinux_9_5",
    [switch]$SkipGuest,
    [string]$TranscriptPath = ""
)

if ($TranscriptPath) { Start-Transcript -Path $TranscriptPath -Force | Out-Null }

$script:Fails = 0
$script:Warns = 0

# ---------------------------------------------------------------------------
# Test harness. Each check calls Test-Item with:
#   -Name    short label
#   -Why     one line: what this proves / why we look at it
#   -Script  scriptblock that returns $true (OK), $false (FAIL), or the string
#            'WARN'/'SKIP'. It may Write-Host raw evidence lines itself.
# ---------------------------------------------------------------------------
function Test-Item {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Why,
        [Parameter(Mandatory)][scriptblock]$Script
    )
    Write-Host ""
    Write-Host "== $Name" -ForegroundColor Cyan
    Write-Host "   why: $Why" -ForegroundColor DarkGray
    $result = $null
    try {
        $result = & $Script
    } catch {
        Write-Host "   error: $_" -ForegroundColor Red
        $result = $false
    }
    switch ("$result") {
        "True"  { Write-Host "   [OK]"   -ForegroundColor Green }
        "False" { Write-Host "   [FAIL]" -ForegroundColor Red;    $script:Fails++ }
        "WARN"  { Write-Host "   [WARN]" -ForegroundColor Yellow; $script:Warns++ }
        "SKIP"  { Write-Host "   [SKIP]" -ForegroundColor DarkGray }
        default { Write-Host "   [FAIL] (check returned '$result')" -ForegroundColor Red; $script:Fails++ }
    }
}

# Run a command inside the guest, return stdout lines. Empty array if the distro
# is not installed / not reachable.
function Invoke-Guest {
    param([string]$Cmd)
    $out = & wsl.exe -d $distroName -- sh -lc $Cmd 2>$null
    return $out
}

# wsl.exe writes some output as UTF-16LE; when captured it comes back with NUL
# bytes between characters. Strip them so regexes match.
function Clear-Nul { param([string[]]$Lines) $Lines | ForEach-Object { $_ -replace "`0", "" } }

# Are we running elevated? Get-HnsNetwork and Get-WindowsOptionalFeature need it.
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
$script:IsAdmin = Test-Admin

# The guest interface that currently holds the default route (mirrored mode does
# NOT guarantee it is eth0 - observed as eth2 on a real machine).
# Note: `ip route get 1.1.1.1` prints "... dev <if> ..." on one line; we parse
# that in PowerShell rather than piping to awk (awk field vars like $5 collide
# with PowerShell string interpolation even when backtick-escaped).
function Get-GuestUplinkIf {
    $line = (Invoke-Guest "ip route get 1.1.1.1 2>/dev/null") -join ' '
    if ($line -match '\bdev\s+(\S+)') { return $Matches[1] }
    $line = (Invoke-Guest "ip route show default 2>/dev/null") -join ' '
    if ($line -match '\bdev\s+(\S+)') { return $Matches[1] }
    return ''
}

# Default gateway IP as seen by the guest.
function Get-GuestGateway {
    $line = (Invoke-Guest "ip route show default 2>/dev/null") -join ' '
    if ($line -match '\bvia\s+(\S+)') { return $Matches[1] }
    return ''
}

function Test-DistroInstalled {
    $names = (& wsl.exe -l -q 2>$null) -join "`n"
    return (($names -split "`r?`n" | ForEach-Object { $_.Trim().Trim([char]0) }) -contains $distroName)
}

Write-Host "### 02_diagnostics.ps1 - WSL / mirrored-networking diagnostics" -ForegroundColor Cyan
Write-Host "### distro under test: $distroName   host: $env:COMPUTERNAME   $(Get-Date -Format s)" -ForegroundColor DarkGray

# ===========================================================================
# HOST-SIDE CHECKS
# ===========================================================================

# --- wsl.exe present -------------------------------------------------------
# EXPECTED: an Application entry at C:\WINDOWS\system32\wsl.exe.
# WHY: everything else depends on it. If missing, the 'Windows Subsystem for
#      Linux' / 'VirtualMachinePlatform' optional features are off and a REBOOT
#      is required after enabling them - no amount of retrying the setup helps.
Test-Item -Name "wsl.exe on PATH" `
  -Why "if absent, WSL optional features are not enabled - needs enable + reboot, not a script retry" `
  -Script {
    $c = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($c) { Write-Host "   $($c.Source)  v$($c.Version)"; $true } else { $false }
}

# --- WSL app package + runtime version -----------------------------------
# EXPECTED: MicrosoftCorporationII.WindowsSubsystemForLinux, Status Ok, and
#           `wsl --version` returns a block (WSL 2.x, kernel 6.6.x).
# WHY: mirrored networking needs WSL >= 2.0.0; the -ENODEV failure and its fix
#      are specific to the 2.x mirrored stack. A working `wsl --version` also
#      proves the optional features are effectively enabled even when we can't
#      query them without elevation.
Test-Item -Name "WSL app package + version" `
  -Why "mirrored mode needs WSL 2.x; a returning `wsl --version` also proves the VM Platform feature is live" `
  -Script {
    $pkg = Get-AppxPackage -Name '*WindowsSubsystemForLinux*' -ErrorAction SilentlyContinue
    $ver = ((Clear-Nul (& wsl.exe --version 2>$null)) -join "`n")
    if ($pkg) { Write-Host "   pkg: $($pkg.Name) $($pkg.Version) [$($pkg.Status)]" }
    if ($ver) { $ver -split "`r?`n" | ForEach-Object { if ($_ -match '\S') { Write-Host "   $($_.Trim())" } } }
    if ($ver -match 'WSL version:\s*2\.') { $true }
    elseif ($ver) { 'WARN' }        # runs, but not the expected 2.x line
    else { $false }
}

# --- hypervisor actually running ---------------------------------------
# EXPECTED: Win32_ComputerSystem.HypervisorPresent = True.
# WHY: WSL2 is a real VM. No hypervisor => no WSL2 => nothing to diagnose.
# NOTE: on a machine where Hyper-V/VBS is on, Win32_Processor
#       .VirtualizationFirmwareEnabled reports FALSE even though VT-x is enabled
#       in firmware - the running hypervisor has claimed the extensions and the
#       OS no longer sees the firmware flag. That FALSE is EXPECTED here and is
#       NOT a finding. HypervisorPresent=True is the check that matters.
Test-Item -Name "Hypervisor present" `
  -Why "WSL2 is a Hyper-V VM; VirtualizationFirmwareEnabled=False is normal once VBS/Hyper-V is running and is not a fault" `
  -Script {
    $hv  = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
    $fw  = (Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled
    Write-Host "   HypervisorPresent            = $hv"
    Write-Host "   VirtualizationFirmwareEnabled= $fw   (False is expected when Hyper-V/VBS is running)"
    [bool]$hv
}

# --- host networking services ----------------------------------------
# EXPECTED: hns Running, vmcompute Running. (LxssManager/WslService vary by
#           build and may be Stopped until first WSL use - that is fine.)
# WHY: mirrored networking is plumbed by HNS (owns the mirrored network object
#      and its per-adapter VMBus endpoints) and vmcompute/HCS (creates the
#      VMBus channels). If mirrored mode is broken, THESE are the services a
#      reboot restarts and `wsl --shutdown` does NOT. If a future fix works by
#      `Restart-Service hns,vmcompute` alone, the stale state was here.
Test-Item -Name "HNS + vmcompute services" `
  -Why "mirrored networking lives in these host services; a reboot restarts them, `wsl --shutdown` does not" `
  -Script {
    $svc = Get-Service hns,vmcompute -ErrorAction SilentlyContinue
    $svc | ForEach-Object { Write-Host ("   {0,-12} {1}" -f $_.Name, $_.Status) }
    $hns = $svc | Where-Object Name -eq 'hns'
    $vmc = $svc | Where-Object Name -eq 'vmcompute'
    if ($hns.Status -eq 'Running' -and $vmc.Status -eq 'Running') { $true } else { $false }
}

# --- HNS network objects -------------------------------------------------
# EXPECTED (WSL running, healthy): at least one HNS network, typically one of
#           type 'ICS'/'Transparent'/'Mirrored' plus the WSL NAT network.
# WHY: during the failure, `Get-HnsNetwork` returned COMPLETELY EMPTY while WSL
#      was still trying to bring up mirrored mode - i.e. HNS was offering a
#      netvsc channel to the guest with no backing network object. An empty
#      list while a distro is running is the strongest host-side signal of the
#      stale-state bug. (Empty while everything is Stopped can be normal - hence
#      WARN, not FAIL, and cross-check with the guest result below.)
Test-Item -Name "HNS network objects present" `
  -Why "empty HNS network list while WSL is running = the stale-endpoint bug that only a reboot clears" `
  -Script {
    if (-not $script:IsAdmin) {
        Write-Host "   needs an elevated shell (Get-HnsNetwork -> Access denied when not admin)"
        Write-Host "   re-run from Administrator PowerShell to include this check"
        return 'SKIP'
    }
    if (-not (Get-Command Get-HnsNetwork -ErrorAction SilentlyContinue)) {
        try { Import-Module HostNetworkingService -ErrorAction Stop }
        catch { try { Import-Module HNS -ErrorAction Stop } catch {} }
    }
    if (-not (Get-Command Get-HnsNetwork -ErrorAction SilentlyContinue)) {
        Write-Host "   Get-HnsNetwork not available on this host"
        return 'WARN'
    }
    $nets = Get-HnsNetwork -ErrorAction SilentlyContinue
    if (-not $nets) {
        Write-Host "   (no HNS networks returned)"
        # Empty while a distro is running is the bug signature; empty while
        # everything is stopped can be normal. Cross-check against the guest.
        if (Test-DistroInstalled -and ((& wsl.exe -l --running 2>$null) -join '' -match '\S')) {
            Write-Host "   -> distro is RUNNING but HNS has no networks: this is the stale-state signature" -ForegroundColor Red
            return $false
        }
        return 'WARN'
    }
    $nets | ForEach-Object { Write-Host ("   {0,-24} type={1}" -f $_.Name, $_.Type) }
    $true
}

# --- adapters + third-party filter drivers ------------------------------
# EXPECTED: your real uplink (e.g. Intel I225-V) Up. Extra virtual adapters
#           (VirtualBox Host-Only, container/endpoint-security vNICs) are
#           informational.
# WHY: mirrored mode enumerates EVERY host adapter and makes a mirrored VMBus
#      endpoint for each. A third-party network filter driver bound to one of
#      those adapters (VirtualBox, or an endpoint-security product such as the
#      'FSE HostVnic' seen on this machine) can produce an endpoint HNS offers
#      but cannot wire through - that becomes the -ENODEV channel. This check
#      just lists them so you can correlate a failing guest VMBus GUID / MAC to
#      a specific Windows adapter.
Test-Item -Name "Host network adapters (inventory)" `
  -Why "mirrored mode mirrors every adapter; a filter driver on one can create the un-backable channel - list them to correlate" `
  -Script {
    Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            Write-Host ("   {0,-34} {1,-9} {2}  [{3}]" -f `
                $_.Name, $_.Status, $_.MacAddress, $_.InterfaceDescription)
        }
    'WARN'   # informational only - never fails, but worth eyeballing
}

# --- .wslconfig networking mode ---------------------------------------
# EXPECTED: [wsl2] networkingMode=mirrored  (this project requires mirrored for
#           k8s / ollama - services must be reachable on the LAN, not NAT-hidden).
# WHY: if a previous troubleshooting step quietly switched this to 'nat', the
#      distro will have working connectivity but via a SINGLE eth0 on a
#      172.x NAT - the -ENODEV root cause is simply NOT being exercised, not
#      fixed. This check records which mode is configured so a "it works now"
#      result can be interpreted correctly.
Test-Item -Name ".wslconfig networkingMode" `
  -Why "project needs mirrored; if it silently reads 'nat', connectivity 'working' does not mean the mirrored bug is fixed" `
  -Script {
    $cfg = Join-Path $env:USERPROFILE '.wslconfig'
    if (-not (Test-Path $cfg)) { Write-Host "   no .wslconfig (WSL default = NAT)"; return 'WARN' }
    $mode = (Select-String -Path $cfg -Pattern '^\s*networkingMode\s*=\s*(\S+)' -ErrorAction SilentlyContinue).Matches.Groups[1].Value
    Write-Host "   networkingMode = $(if ($mode) { $mode } else { '(unset -> nat)' })"
    Get-Content $cfg | ForEach-Object { Write-Host "   | $_" }
    if ($mode -eq 'mirrored') { $true } else { 'WARN' }
}

# ===========================================================================
# GUEST-SIDE CHECKS  (skipped cleanly if distro absent or -SkipGuest)
# ===========================================================================
$runGuest = -not $SkipGuest
if ($runGuest -and -not (Test-DistroInstalled)) {
    Write-Host ""
    Write-Host "== guest checks" -ForegroundColor Cyan
    Write-Host "   $distroName is not installed - guest checks skipped" -ForegroundColor DarkGray
    $runGuest = $false
}

if ($runGuest) {

  # --- default route present -----------------------------------------
  # EXPECTED: a `default via <gw> dev ethX` line.
  # WHY: in the failure state the routing table was EMPTY (all eth* DOWN). A
  #      present default route is the single best positive proof the network
  #      came up. DNS config (resolv.conf) is orthogonal - it can look fine
  #      while routing is dead. This check is evaluated BEFORE the netvsc check
  #      below, because the netvsc verdict depends on it.
  $script:GuestHasRoute = $false
  Test-Item -Name "guest: default route exists" `
    -Why "failure state had an empty routing table with every eth* DOWN; a default route proves the NIC came up" `
    -Script {
      $r = Invoke-Guest "ip route 2>/dev/null"
      $r | ForEach-Object { Write-Host "   $_" }
      $ok = [bool]($r -match '^default via ')
      $script:GuestHasRoute = $ok
      $ok
  }

  # --- kernel netvsc / vmbus log ------------------------------------
  # EXPECTED on a HEALTHY machine: there MAY be `unable to open channel: -19`
  #   lines for ONE netvsc device - that is normal (see the header note). What
  #   must also be true is that a default route exists (previous check).
  # FAIL only when: -ENODEV present AND no default route -> the un-backable
  #   channel took out the uplink and nothing covered it. THIS is the state
  #   that a Windows reboot (not `wsl --shutdown`) fixes.
  # WARN when: -ENODEV present but routing is fine (cosmetic; note the GUID -
  #   it is one of the mirrored WAN Miniport / disconnected-Wi-Fi virtuals).
  # WHY: -19 = -ENODEV on vmbus_open() for a netvsc channel = host offered a
  #   mirrored NIC channel it cannot back.
  Test-Item -Name "guest: netvsc -ENODEV vs. connectivity" `
    -Why "a lone -ENODEV is normal (one un-backable mirrored virtual); it is a FAILURE only when it also killed the default route" `
    -Script {
      $log = Invoke-Guest "dmesg 2>/dev/null | grep -iE 'hv_netvsc|hv_vmbus|netvsc' || true"
      $bad = $log | Where-Object { $_ -match 'unable to open channel: -19|probe failed for device .*\(-19\)' }
      if (-not $bad) { Write-Host "   (no -ENODEV netvsc errors)"; return $true }

      $guids = ($bad | Select-String -Pattern '([0-9a-f-]{36})' -AllMatches).Matches.Value | Select-Object -Unique
      $bad | Select-Object -First 4 | ForEach-Object { Write-Host "   $_" }
      Write-Host "   affected VMBus GUID(s): $($guids -join ', ')"

      if ($script:GuestHasRoute) {
          Write-Host "   default route is present -> other mirrored NICs came up; this is cosmetic" -ForegroundColor Yellow
          return 'WARN'
      }
      Write-Host "   NO default route AND -ENODEV -> the un-backable channel took the uplink" -ForegroundColor Red
      Write-Host "   -> save this output + guest 'dmesg' + (elevated) Get-HnsNetwork/Get-HnsEndpoint, then REBOOT Windows" -ForegroundColor Yellow
      return $false
  }

  # --- which mode actually came up ---------------------------------
  # EXPECTED for mirrored: the uplink interface (whichever holds the default
  #          route - observed as eth2, NOT necessarily eth0) is on the HOST LAN
  #          (same subnet as the Windows box, e.g. 192.168.7.0/24) and there are
  #          per-interface `ip rule` policy entries (from all iif <if> lookup
  #          local). NAT mode instead shows a single eth0 on 172.x with gateway
  #          172.x and no such ip rules.
  # WHY: distinguishes "mirrored is genuinely working" from "fell back to NAT".
  #      Both give internet; only mirrored gives LAN-reachable k8s/ollama.
  # NOTE: MTU 1488 was seen once as a mirrored-mode tell, but a healthy mirrored
  #       run has also shown MTU 1500 - so MTU is logged, not asserted. The
  #       reliable signals are LAN subnet match + presence of iif ip rules.
  Test-Item -Name "guest: mirrored mode is really active (not NAT fallback)" `
    -Why "mirrored => uplink on the host LAN + per-iface ip rules; NAT => single 172.x eth0 with none - only mirrored suits k8s/ollama" `
    -Script {
      $upif = Get-GuestUplinkIf
      if (-not $upif) { Write-Host "   no uplink interface (no default route)"; return $false }
      $gw   = Get-GuestGateway
      $addr = Invoke-Guest "ip -o addr show dev $upif 2>/dev/null"
      $mtu  = ("$(Invoke-Guest "cat /sys/class/net/$upif/mtu 2>/dev/null")").Trim()
      # Count policy-routing rules that scope traffic per-interface (a mirrored-mode
      # signature). Fetch all rules, filter in PowerShell to avoid nested quoting.
      $rule = @(Invoke-Guest "ip rule list 2>/dev/null" | Where-Object { $_ -match "iif\s+$upif\b" }).Count
      $addr | ForEach-Object { Write-Host "   $_" }
      Write-Host "   uplink=$upif  mtu=$mtu  gw=$gw  ip-rules(iif $upif)=$rule"
      $isNat = ($gw -match '^172\.') -and ($rule -eq 0)
      if ($isNat) {
          Write-Host "   -> NAT fallback: gw is 172.x and no per-iface ip rules. Internet works but not LAN-visible." -ForegroundColor Yellow
          return 'WARN'
      }
      if ($rule -gt 0 -or $gw -notmatch '^172\.') { $true } else { 'WARN' }
  }

  # --- HTTPS egress to the package repos ---------------------------
  # EXPECTED: HTTP 200 from yum.oracle.com and a general HTTPS host.
  # WHY: the setup FIRST broke at `03_set_update.sh` with
  #      'curl error 7: Couldn't connect' - i.e. DNS resolved but there was no
  #      route. This check reproduces exactly that step so a green run here
  #      means `03_set_update.sh` / dnf will succeed.
  Test-Item -Name "guest: HTTPS to yum.oracle.com" `
    -Why "the setup first failed here with curl error 7 (no route); a 200 means dnf / 03_set_update.sh will work" `
    -Script {
      $code = Invoke-Guest "curl -sS -m 15 -o /dev/null -w '%{http_code}' https://yum.oracle.com/ 2>/dev/null"
      Write-Host "   https://yum.oracle.com -> HTTP $code"
      if ("$code" -match '^(200|301|302)$') { $true } else { $false }
  }

  # --- corporate CA interception awareness -----------------------
  # EXPECTED: informational. Lists any trusted root that looks like a TLS
  #           interception / proxy CA.
  # WHY: 04_set_certs.sh imports the Windows trust store (68 certs on this box)
  #      into the distro. If one is a MITM/proxy root, HTTPS FROM INSIDE WSL is
  #      inspectable - WSL traffic is NOT a private tunnel. Not a fault, but you
  #      should know it is there.
  Test-Item -Name "guest: TLS-interception root in trust store?" `
    -Why "04_set_certs.sh copies the Windows trust store in; a proxy/MITM root means WSL HTTPS is inspected, not private" `
    -Script {
      $hits = Invoke-Guest "trust list 2>/dev/null | grep -iE 'proxy|inspect|zscaler|netskope|bluecoat|forcepoint|palo alto|fortinet|mitm' || true"
      if ($hits) {
          $hits | ForEach-Object { Write-Host "   $_" -ForegroundColor Yellow }
          Write-Host "   -> WSL HTTPS egress is subject to TLS inspection (expected on a managed host)" -ForegroundColor Yellow
      } else {
          Write-Host "   (no obvious interception CA by name - not conclusive)"
      }
      'WARN'
  }
}

# ===========================================================================
# SUMMARY
# ===========================================================================
Write-Host ""
Write-Host "### summary: $script:Fails FAIL, $script:Warns WARN" -ForegroundColor $(if ($script:Fails) { 'Red' } else { 'Green' })
if (-not $script:IsAdmin) {
    Write-Host "### note: not elevated - HNS check was skipped. Re-run from Administrator PowerShell for full coverage." -ForegroundColor DarkGray
}
if ($script:Fails -and $runGuest) {
    Write-Host "### a FAIL involving no default route + netvsc -ENODEV means the mirrored uplink channel is un-backable." -ForegroundColor Yellow
    Write-Host "### capture: guest 'dmesg > /mnt/c/temp/wsl-dmesg.txt', 'ip -details link', and (elevated)" -ForegroundColor Yellow
    Write-Host "###   Get-HnsNetwork|ConvertTo-Json -Depth 6, Get-HnsEndpoint|ConvertTo-Json -Depth 6" -ForegroundColor Yellow
    Write-Host "### THEN reboot Windows. 'wsl --shutdown' alone does NOT clear host HNS/vmbus state." -ForegroundColor Yellow
}

if ($TranscriptPath) { Stop-Transcript | Out-Null; Write-Host "### transcript: $TranscriptPath" -ForegroundColor DarkGray }

exit $script:Fails
