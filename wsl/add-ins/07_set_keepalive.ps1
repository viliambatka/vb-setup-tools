<#
.SYNOPSIS
    Keeps a WSL distribution running once started (no interactive session needed)
.DESCRIPTION
    Installs an in-guest systemd unit whose only job is to hold a live process
    (`/bin/sleep infinity`) inside the distro, so the WSL VM has a reason to stay
    up when nobody is logged in.

    This is the companion to 06_set_boot_task.ps1, and the two are NOT
    interchangeable:

      06_set_boot_task.ps1  starts the distro at host boot   (no logon required)
      07_set_keepalive.ps1  keeps it running once started    (no session required)

    Without the keepalive an idle distro still stops ~80s after its last session
    closes. .wslconfig `vmIdleTimeout=-1` does NOT prevent that on its own — it
    governs the utility VM idle timer, not the distro — so the two complement
    each other. Verified: with vmIdleTimeout=-1 set but no keepalive, an
    otherwise idle VM still went Stopped within 100s of boot.

    Requires systemd inside the distro (`[boot] systemd=true` in /etc/wsl.conf,
    which 01_set_wslconfig.ps1 / 07_set_system.sh configure). If PID 1 is not
    systemd the script reports it and exits non-zero rather than pretending to
    have installed anything.

    Idempotent: re-running leaves an existing, healthy unit alone.
.PARAMETER distroName
    WSL distribution to keep alive (default: "OracleLinux_8_10")
.PARAMETER unitName
    systemd unit name (default: "wsl-keepalive.service")
.PARAMETER remove
    Disables and deletes the unit instead of installing it
.PARAMETER force
    Rewrites the unit file even when it already exists
.EXAMPLE
    .\07_set_keepalive.ps1 -distroName OracleLinux_8_10
.EXAMPLE
    .\07_set_keepalive.ps1 -remove
.NOTES
    Writes to /etc/systemd/system inside the distro as root via `wsl -u root`,
    which does not require an elevated Windows shell.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$distroName = "OracleLinux_8_10",
    [string]$unitName = "wsl-keepalive.service",
    [switch]$remove,
    [switch]$force
)

Write-Host "### 07_set_keepalive.ps1 - Keepalive '$unitName' for $distroName" -ForegroundColor Cyan

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] WSL not available. Enable the WSL feature and reboot."
    exit 1
}

# The distro must exist before we try to write a unit into it. `wsl -l -q` output is
# UTF-16 with embedded NULs when captured, so strip them before comparing.
$distros = (& wsl.exe -l -q) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($distros -notcontains $distroName) {
    Write-Error "[ERROR] Distro '$distroName' not found. Run 00_quick_start.ps1 first. Present: $($distros -join ', ')"
    exit 1
}

# --- removal path ---
if ($remove) {
    if ($PSCmdlet.ShouldProcess($distroName, "remove $unitName")) {
        $rm = @"
set -uo pipefail
UNIT=/etc/systemd/system/$unitName
if [ -f "`$UNIT" ]; then
  systemctl disable --now $unitName >/dev/null 2>&1 || true
  rm -f "`$UNIT"
  systemctl daemon-reload || true
  echo "removed `$UNIT"
else
  echo "`$UNIT not present - nothing to remove"
fi
"@
        (& wsl.exe -d $distroName -u root -e bash -lc $rm 2>&1) | ForEach-Object { Write-Host "- $_" }
        Write-Host "[SUCCESS] Keepalive removed from $distroName" -ForegroundColor Green
    }
    exit 0
}

# systemd is a hard prerequisite: without it there is no unit to enable, and a
# silent no-op here would look like the gap was closed when it was not.
$pid1 = ((& wsl.exe -d $distroName -e bash -lc 'cat /proc/1/comm 2>/dev/null') -replace "`0", '').Trim()
if ($pid1 -notmatch 'systemd') {
    Write-Error @"
[ERROR] systemd is not PID 1 in $distroName (found: '$pid1').
        Enable it in /etc/wsl.conf:   [boot]`n        systemd=true
        then run:  wsl --shutdown     (this stops the distro - do not do it while a job is running)
        See add-ins/07_set_system.sh, or run 00_quick_start.ps1.
"@
    exit 1
}

if ($PSCmdlet.ShouldProcess($distroName, "install $unitName")) {
    # Heredoc executed as root inside the distro. `force` rewrites the unit file;
    # otherwise an existing file is left untouched and only the enable is re-asserted.
    $forceFlag = if ($force) { '1' } else { '0' }
    $script = @"
set -euo pipefail
UNIT=/etc/systemd/system/$unitName
FORCE=$forceFlag
if [ ! -f "`$UNIT" ] || [ "`$FORCE" = "1" ]; then
  cat > "`$UNIT" <<'UNITEOF'
[Unit]
Description=WSL VM keepalive (holds the distro up with no interactive session)
After=multi-user.target

[Service]
Type=simple
ExecStart=/bin/sleep infinity
Restart=always

[Install]
WantedBy=multi-user.target
UNITEOF
  echo "wrote `$UNIT"
else
  echo "`$UNIT already exists (use -force to rewrite)"
fi
systemctl daemon-reload
systemctl enable --now $unitName
echo "state: `$(systemctl is-enabled $unitName 2>/dev/null) / `$(systemctl is-active $unitName 2>/dev/null)"
"@
    $out = & wsl.exe -d $distroName -u root -e bash -lc $script 2>&1
    $out | ForEach-Object { Write-Host "- $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] Keepalive install failed (exit $LASTEXITCODE)."
        exit 1
    }
    Write-Host "[SUCCESS] $distroName will stay up with no interactive session!" -ForegroundColor Green
    Write-Host "  Verify: wsl -d $distroName -e systemctl is-active $unitName" -ForegroundColor DarkGray
}
