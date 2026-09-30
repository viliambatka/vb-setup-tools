#!/usr/bin/env bash
# Install PowerShell 7 on Oracle Linux 9 using Microsoft's RHEL 9 package repo.
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "Cannot identify this Linux distribution." >&2
    exit 1
fi

source /etc/os-release
if [[ "${ID:-}" != "ol" || "${VERSION_ID%%.*}" != "9" ]]; then
    echo "This installer targets Oracle Linux 9; found ${PRETTY_NAME:-unknown}." >&2
    exit 1
fi

dnf install -y https://packages.microsoft.com/config/rhel/9/packages-microsoft-prod.rpm
dnf install -y powershell

pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'