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
- **09_fix_interop_and_drive_metadata.sh** - Fix two boot-time quirks: WSLInterop
  (binfmt_misc) not surviving a restart with `systemd=true`, and a mounted Windows drive
  not supporting `chmod`/`chown`/`chtimes` (DrvFs without the `metadata` option). Run as
  root inside the distro: `sudo bash ./09_fix_interop_and_drive_metadata.sh [DRIVE_LETTER]`
  (default `J`). Takes effect after `wsl --shutdown` + reopening the distro.
- **10_update_ollama.sh** - Update (or install) the WSL-side Ollama via the official
  install script. Separate from the Windows Ollama install — updating one does not
  update the other. Preserves `OLLAMA_MODELS`/`OLLAMA_CONTEXT_LENGTH` and ensures
  `OLLAMA_KEEP_ALIVE=-1` is set in the systemd drop-in (default 5m idle timeout
  otherwise unloads the model between queries, paying a full reload from `/mnt/j`
  each time). Run as root inside the distro: `sudo bash ./10_update_ollama.sh`
  (full install/update) or `sudo bash ./10_update_ollama.sh --keepalive-only` (just
  the keep-alive setting, no reinstall, idempotent).

### Install PowerShell 7 in Oracle Linux 9

From the repository root, run the installer inside the WSL distro as root:

```bash
cd /mnt/j/sd_src/repo/vb-bb-targets/vb-setup-tools/wsl/add-ins
sudo bash ./08_install_pwsh.sh
```

The installer adds Microsoft's RHEL 9 package repository, installs the `powershell`
package with `dnf`, and prints the installed `pwsh` version.

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
[SOP-15](../../kb/sop/15-pipeline-automation.md).

## - CA Certificates

Export Windows certificates to WSL for corporate environments:

```powershell
# Export all certificates and configure WSL
.\add-ins\04_set_certs.ps1

# Root certificates only
.\add-ins\04_set_certs.ps1 -rootOnly

# Custom export path
.\add-ins\04_set_certs.ps1 -exportPath "C:\certs\ca-bundle.crt"
```

## 💿 ISO Repository

`add-ins/05_set_iso_repo.ps1` is a placeholder — not yet implemented (empty file). Until it
lands, configure an offline yum/dnf repo from an Oracle Linux ISO manually inside the distro:

```bash
# Mount the ISO and point yum/dnf at it, then install packages offline
yum install gcc make kernel-devel
yum list available
```

## Links

- [Oracle Linux ISOs](https://yum.oracle.com/oracle-linux-isos.html)