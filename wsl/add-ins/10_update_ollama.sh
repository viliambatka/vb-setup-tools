#!/usr/bin/env bash
# Update (or install) the WSL-side Ollama. This is a SEPARATE binary/service from the
# Windows Ollama install (C:\...\AppData\Local\Programs\Ollama\ollama.exe) — updating
# one does not update the other, and a version mismatch between them is otherwise only
# noticed indirectly (e.g. `ollama.exe create` printing "ollama version is 0.34.1 /
# Warning: client version is 0.34.4" when the WSL server is older than the Windows
# client talking to it over the same localhost port).
#
# Uses Ollama's own official install script, which detects an existing installation
# and upgrades it in place (replaces /usr/local/bin/ollama and the base systemd unit,
# then restarts the service). It does NOT touch this machine's systemd drop-in
# (/etc/systemd/system/ollama.service.d/override.conf — OLLAMA_MODELS, OLLAMA_CONTEXT_LENGTH),
# since that lives in a separate file the base unit includes.
#
# Usage:
#   sudo bash ./10_update_ollama.sh

set -euo pipefail

echo "### 10_update_ollama.sh"

msg() { printf '%s\n' "$*"; }
die() { msg "[ERROR] $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo $0"

if command -v ollama >/dev/null 2>&1; then
  msg "Current version: $(ollama --version 2>&1 | head -n1)"
else
  msg "Ollama not currently installed in WSL — this will install it fresh."
fi

msg "Downloading and running the official install/update script ..."
curl -fsSL https://ollama.com/install.sh | sh

msg "[OK] Installed/updated. New version:"
ollama --version 2>&1 | head -n1

if command -v systemctl >/dev/null 2>&1 && [ -f /proc/1/comm ] && grep -qi systemd /proc/1/comm; then
  systemctl is-active --quiet ollama && msg "[OK] ollama.service is active" \
    || msg "[WARN] ollama.service not active — check: systemctl status ollama"
else
  msg "[WARN] systemd not active (PID 1) — run 'wsl --shutdown' from Windows to apply"
fi

msg "[DONE] Verify the drop-in config survived: cat /etc/systemd/system/ollama.service.d/override.conf"
