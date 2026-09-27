#!/usr/bin/env bash
# Read-only: why does WSL fail to run Windows .exe files ("Exec format error")?
# Article: kb/wsl/windows-exe-exec-format-error.md
# Healthy = a WSLInterop entry in /proc/sys/fs/binfmt_misc and `cmd.exe /c ver` prints a version.
# Usage (WSL):  bash vb-setup-tools/scripts/diagnostics/check_interop.sh
echo "--- /etc/wsl.conf"; cat /etc/wsl.conf 2>/dev/null || echo "(none)"
echo "--- binfmt_misc mounted?"; mount | grep binfmt_misc || echo "(not mounted)"
echo "--- binfmt_misc entries"; ls /proc/sys/fs/binfmt_misc/ 2>/dev/null || echo "(unreadable)"
echo "--- WSLInterop entry"; cat /proc/sys/fs/binfmt_misc/WSLInterop 2>/dev/null || echo "(no WSLInterop entry)"
echo "--- WSLInterop-late entry"; cat /proc/sys/fs/binfmt_misc/WSLInterop-late 2>/dev/null || echo "(none)"
echo "--- /init present?"; ls -l /init 2>/dev/null || echo "(no /init)"
echo "--- systemd PID 1?"; ps -o comm= -p 1
echo "--- systemd-binfmt"; systemctl is-active systemd-binfmt.service 2>&1; ls /usr/lib/binfmt.d/ /etc/binfmt.d/ 2>/dev/null
echo "--- WSL_INTEROP / WSL_DISTRO_NAME"; echo "WSL_INTEROP=${WSL_INTEROP:-unset} WSL_DISTRO_NAME=${WSL_DISTRO_NAME:-unset}"
echo "--- try cmd.exe"; /mnt/c/Windows/System32/cmd.exe /c ver 2>&1 | tr -d '\r' | head -3
