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
# then restarts the service). The install itself does NOT touch this machine's systemd
# drop-in (/etc/systemd/system/ollama.service.d/override.conf — OLLAMA_MODELS,
# OLLAMA_CONTEXT_LENGTH), since that lives in a separate file the base unit includes —
# but this script ALSO ensures OLLAMA_KEEP_ALIVE=-1 is set there (see below), since an
# update is a natural point to also confirm the drop-in is complete.
#
# OLLAMA_KEEP_ALIVE=-1: without it, Ollama's 5-minute default idle timeout unloads the
# model between queries whenever more than 5 minutes passes (easy with multi-minute
# response times on this machine's model store, /mnt/j — a WSL-mounted Windows drive),
# so the NEXT query pays a full reload from that slow mount all over again. -1 keeps
# a loaded model in VRAM indefinitely once loaded, trading permanently-held VRAM for
# never re-paying that cold-load cost mid-conversation.
#
# Usage:
#   sudo bash ./10_update_ollama.sh                 # full install/update, then set keep-alive
#   sudo bash ./10_update_ollama.sh --keepalive-only # ONLY set keep-alive, no install/update
#                                                     # (idempotent, fast — use this to apply
#                                                     # just the setting without reinstalling)

set -euo pipefail

msg() { printf '%s\n' "$*"; }
die() { msg "[ERROR] $*"; exit 1; }

KEEPALIVE_ONLY=0
[ "${1:-}" = "--keepalive-only" ] && KEEPALIVE_ONLY=1

OVERRIDE_CONF=/etc/systemd/system/ollama.service.d/override.conf

set_keep_alive() {
  local need_restart=0
  if [ -f "$OVERRIDE_CONF" ] && grep -q '^Environment="OLLAMA_KEEP_ALIVE=-1"$' "$OVERRIDE_CONF"; then
    msg "[OK] OLLAMA_KEEP_ALIVE=-1 already set in $OVERRIDE_CONF"
  elif [ -f "$OVERRIDE_CONF" ]; then
    if grep -q '^Environment="OLLAMA_KEEP_ALIVE=' "$OVERRIDE_CONF"; then
      sed -i 's/^Environment="OLLAMA_KEEP_ALIVE=.*/Environment="OLLAMA_KEEP_ALIVE=-1"/' "$OVERRIDE_CONF"
    else
      printf 'Environment="OLLAMA_KEEP_ALIVE=-1"\n' >> "$OVERRIDE_CONF"
    fi
    msg "[OK] Set OLLAMA_KEEP_ALIVE=-1 in $OVERRIDE_CONF"
    need_restart=1
  else
    msg "[WARN] $OVERRIDE_CONF does not exist — OLLAMA_MODELS/OLLAMA_CONTEXT_LENGTH are not set either."
    msg "       Create it first (see vb-setup-tools/wsl/add-ins/09_fix_interop_and_drive_metadata.sh"
    msg "       or set it up manually), then re-run this script."
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1 && [ -f /proc/1/comm ] && grep -qi systemd /proc/1/comm; then
    if [ "$need_restart" = "1" ]; then
      systemctl daemon-reload
      systemctl restart ollama
      msg "[OK] Restarted ollama.service to apply OLLAMA_KEEP_ALIVE"
    fi
    systemctl is-active --quiet ollama && msg "[OK] ollama.service is active" \
      || msg "[WARN] ollama.service not active — check: systemctl status ollama"
  else
    msg "[WARN] systemd not active (PID 1) — run 'wsl --shutdown' from Windows to apply"
  fi
}

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo $0"

if [ "$KEEPALIVE_ONLY" = "1" ]; then
  echo "### 10_update_ollama.sh --keepalive-only"
  set_keep_alive
  msg "[DONE] Verify the drop-in config: cat $OVERRIDE_CONF"
  exit 0
fi

echo "### 10_update_ollama.sh"

if command -v ollama >/dev/null 2>&1; then
  msg "Current version: $(ollama --version 2>&1 | head -n1)"
else
  msg "Ollama not currently installed in WSL — this will install it fresh."
fi

msg "Downloading and running the official install/update script ..."
curl -fsSL https://ollama.com/install.sh | sh

msg "[OK] Installed/updated. New version:"
ollama --version 2>&1 | head -n1

set_keep_alive

msg "[DONE] Verify the drop-in config: cat $OVERRIDE_CONF"
