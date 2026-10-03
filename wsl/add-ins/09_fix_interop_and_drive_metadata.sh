#!/usr/bin/env bash
# Fix two boot-time WSL quirks that otherwise need to be re-applied by hand after every
# `wsl --shutdown` / distro reinstall:
#
#   1) WSLInterop (binfmt_misc) does not survive boot when systemd=true is set in
#      /etc/wsl.conf — systemd remounts binfmt_misc and drops the handler WSL registered,
#      so any Windows .exe called from this distro fails with "Exec format error".
#      Fix: register it via /etc/binfmt.d/ so systemd-binfmt re-registers it itself at boot.
#
#   2) Windows drives are mounted via DrvFs without the `metadata` option, so this distro
#      cannot chmod/chown/chtimes files on them (fails "operation not permitted"). This
#      breaks any tool that writes files there and then sets permissions/mtime on them —
#      found via `ollama create` writing its blob store to a mounted Windows drive.
#      Fix: a oneshot systemd unit that remounts the given drive with -o metadata after
#      WSL's own automount has mounted it plainly.
#
# See: vb-setup-tools/kb/wsl/windows-exe-exec-format-error.md

set -euo pipefail

msg() { printf '%s\n' "$*"; }
die() { msg "[ERROR] $*"; exit 1; }

drive_letter="${1:-J}"
drive_letter="${drive_letter%:}"
mnt_point="/mnt/$(echo "$drive_letter" | tr '[:upper:]' '[:lower:]')"
unit_name="remount-${drive_letter,,}-metadata.service"

# Already applied? Exit before the sudo/root check so a wrapper can call this on every
# setup run without prompting for a password each time once the fixes are in place.
if [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] \
   && [ -f /etc/systemd/system/"$unit_name" ] \
   && mount | grep -q "on $mnt_point .*metadata"; then
  echo "### 09_fix_interop_and_drive_metadata.sh - already applied, nothing to do"
  exit 0
fi

echo "### 09_fix_interop_and_drive_metadata.sh"

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo $0 [DRIVE_LETTER]"

# Confirm the drive before touching mount config — a wrong guess here reconfigures the
# wrong Windows drive's mount behavior. Skip with BB_WSL_FIX_YES=1 (e.g. from a
# non-interactive setup script that already derived the drive itself).
if [ "${BB_WSL_FIX_YES:-0}" != "1" ] && [ -t 0 ]; then
  read -r -p "About to fix WSLInterop and remount ${drive_letter}: (${mnt_point}) with -o metadata. Continue? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) msg "Aborted — no changes made."; exit 1 ;;
  esac
fi

# 1) WSLInterop — register via /etc/binfmt.d/ so systemd-binfmt re-applies it on every boot.
binfmt_conf=/etc/binfmt.d/WSLInterop.conf
if [ -f "$binfmt_conf" ] && grep -q ':WSLInterop:M::MZ::/init:' "$binfmt_conf"; then
  msg "[OK] $binfmt_conf already registers WSLInterop"
else
  mkdir -p /etc/binfmt.d
  echo ':WSLInterop:M::MZ::/init:PF' > "$binfmt_conf"
  msg "[OK] Wrote $binfmt_conf"
fi
if command -v systemctl >/dev/null 2>&1 && [ -f /proc/1/comm ] && grep -qi systemd /proc/1/comm; then
  systemctl restart systemd-binfmt || msg "[WARN] systemd-binfmt restart failed — will take effect on next boot"
else
  msg "[WARN] systemd not active (PID 1) — run 'wsl --shutdown' from Windows to apply"
fi
if [ -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then
  msg "[OK] WSLInterop is currently registered"
else
  msg "[WARN] WSLInterop not registered yet — takes effect after the next 'wsl --shutdown'"
fi

# 2) Drive metadata mount — a oneshot unit remounts $mnt_point with -o metadata after boot.
[ -d "$mnt_point" ] || die "$mnt_point does not exist — is drive $drive_letter: mounted in WSL?"

unit="/etc/systemd/system/$unit_name"
cat > "$unit" << EOF
[Unit]
Description=Remount ${mnt_point} with DrvFs metadata option (enables chmod/chown/chtimes)
After=local-fs.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/bin/mount -t drvfs ${drive_letter}: ${mnt_point} -o metadata,uid=1000,gid=1000
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
msg "[OK] Wrote $unit"

if command -v systemctl >/dev/null 2>&1 && [ -f /proc/1/comm ] && grep -qi systemd /proc/1/comm; then
  systemctl daemon-reload
  systemctl enable "$(basename "$unit")"
  msg "[OK] Enabled $(basename "$unit")"
else
  msg "[WARN] systemd not active (PID 1) — unit will enable and run on next boot after 'wsl --shutdown'"
fi

msg "[DONE] Run 'wsl --shutdown' from Windows, reopen the distro, then verify:"
msg "       mount | grep $mnt_point    # should show 'metadata' in the options, not stacked"
msg "       cmd.exe /c ver             # confirms interop works"
