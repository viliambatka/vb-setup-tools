# WSL Scripts 🐧

Windows Subsystem for Linux setup and configuration.

## Quick Start

```powershell
# Complete WSL setup (Oracle Linux)
.\00_quick_start.ps1

# Custom distribution
.\01_set_wsl.ps1 -distroName "OracleLinux_8_10" -setdefault
```

## Scripts

- **00_quick_start.ps1** - Complete automated setup
- **01_set_wsl.ps1** - Distribution install/detect and config
- **02_set_dns.sh** - DNS configuration (runs as root)
- **04_configure_ca_certs.ps1** - Windows CA certificate export/config
- **05_setup_iso_repo.ps1** - Local ISO repository setup
- **tast_scheduler/01_set_start_wsl_task.ps1** - Scheduled task to start WSL at logon or startup

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
