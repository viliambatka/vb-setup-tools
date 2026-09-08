# WSL Scripts 🐧

Windows Subsystem for Linux setup and configuration.

## Quick Start

```powershell
# Complete WSL setup (Oracle Linux)
.\00_quick_start.ps1

# Same, plus start the distro at host boot (needs an elevated shell)
.\00_quick_start.ps1 -bootTask

# Custom distribution
.\01_set_wsl.ps1 -distroName "OracleLinux_9_5" -setdefault
```

## Scripts

- **00_quick_start.ps1** - Complete automated setup
- **01_set_wsl.ps1** - Distribution install/detect and config

### add-ins/

- **01_set_wslconfig.ps1** - `%USERPROFILE%\.wslconfig` `[wsl2]` settings (networking, idle timeout, memory)
- **02_set_dns.ps1** / **02_set_dns.sh** - DNS configuration (the `.sh` runs as root inside the distro)
- **03_set_update.ps1** - Update the distro and install base tools
- **04_set_certs.ps1** - Windows CA certificate export/config
- **05_set_iso_repo.ps1** - Local ISO repository setup
- **06_set_boot_task.ps1** - Start the distro automatically at host boot

## 🔌 Start at host boot

Registers a **SYSTEM** scheduled task with an at-startup trigger, so the distro comes
up without anyone logging in — the difference that matters after an unattended reboot
(e.g. Windows Update at night). A per-user task only fires after a sign-in.

```powershell
# Elevated PowerShell
.\add-ins\06_set_boot_task.ps1 -distroName OracleLinux_9_5
.\add-ins\06_set_boot_task.ps1 -remove        # undo
```

**Starting the distro is not the same as keeping it up.** An idle distro still stops
~80s after its last session closes, and `.wslconfig` `vmIdleTimeout=-1` does *not*
prevent that — it governs the utility VM, not the distro. Workloads that need
continuous uptime (a self-hosted CI runner, a long-running service) also need an
in-guest keepalive; see
[SOP-15](../../instructions/sop/15-pipeline-automation.md).

## - CA Certificates

Export Windows certificates to WSL for corporate environments:

```powershell
# Export all certificates and configure WSL
.\04_configure_ca_certs.ps1

# Root certificates only
.\04_configure_ca_certs.ps1 -rootOnly

# Custom export path
.\04_configure_ca_certs.ps1 -exportPath "C:\certs\ca-bundle.crt"
```

## 💿 ISO Repository

Use Oracle Linux ISO as local package repository:

```powershell
# Setup ISO repo (download from oracle.com/linux)
.\05_setup_iso_repo.ps1 -isoPath "C:\ISOs\OracleLinux-R8-U10-x86_64-dvd.iso"

# Permanent mount + replace online repos
.\05_setup_iso_repo.ps1 -isoPath "C:\ISOs\oracle.iso" -permanent -replaceRepos
```

```bash
# Install packages offline
yum install gcc make kernel-devel
yum list available
```

## Links

- [Oracle Linux ISOs](https://yum.oracle.com/oracle-linux-isos.html)