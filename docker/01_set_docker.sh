#!/usr/bin/env bash
# Install Docker Engine inside WSL (Oracle Linux 8 / Ubuntu)
set -euo pipefail

echo "### 01_set_docker.sh - Installing Docker Engine..."

msg() { printf '%s\n' "$*"; }
die() { msg "[ERROR] $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Must run as root"

FORCE_MODE="${FORCE_MODE:-false}"
WSL_DOCKER_USER="${WSL_DOCKER_USER:-}"

if command -v docker >/dev/null 2>&1 && [ "$FORCE_MODE" != "true" ]; then
  msg "[OK] Docker already installed: $(docker --version)"
  exit 0
fi

# Detect distro family
is_ubuntu=false
if [ -r /etc/os-release ]; then
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) is_ubuntu=true ;;
  esac
fi

if $is_ubuntu; then
  msg "- Detected Debian/Ubuntu; installing docker.io"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y docker.io
else
  msg "- Detected RPM-based distro; installing Docker CE"
  if command -v dnf >/dev/null 2>&1; then
    dnf -y install dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif command -v yum >/dev/null 2>&1; then
    yum -y install yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    die "Unsupported package manager; expected dnf or yum"
  fi
fi

# systemd is required for a reliable dockerd in WSL
if [ -f /proc/1/comm ] && grep -qi systemd /proc/1/comm; then
  msg "- Enabling and starting docker service"
  systemctl enable --now docker
  systemctl is-active --quiet docker || die "docker service not active"
else
  msg "[WARN] systemd is not active inside WSL (PID 1 is not systemd)."
  msg "       From Windows run: wsl --shutdown"
  msg "       Then re-open the distro and rerun this installer."
  exit 2
fi

# Add user to docker group for non-root usage
if [ -n "$WSL_DOCKER_USER" ] && id "$WSL_DOCKER_USER" >/dev/null 2>&1; then
  msg "- Adding user '$WSL_DOCKER_USER' to docker group"
  groupadd -f docker
  usermod -aG docker "$WSL_DOCKER_USER" || true
  msg "[OK] User added. You may need to restart your WSL session."
fi

msg "[OK] Docker installed: $(docker --version)"
