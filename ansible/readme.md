# Ansible Scripts 🤖

Ansible installation and configuration for WSL/Oracle Linux.

## Quick Start

```powershell
# Complete Ansible setup (installs WSL if missing)
.\00_quick_start.ps1

# Custom WSL distribution
.\00_quick_start.ps1 -distroName "OracleLinux_9_5"

# Force reinstall
.\00_quick_start.ps1 -forse
```

## [OK] What Happens

1. **WSL Setup** - Ensures Oracle Linux availability
2. **System Updates** - Packages + Python/pip installation
3. **Ansible Installation** - Latest Ansible via pip
4. **Configuration** - Basic ansible.cfg and inventory
5. **Collections** - Common Ansible collections pre-installed
6. **User Setup** - Dedicated ansible user

## Usage

```bash
# Test connection
ansible localhost -m ping

# Run playbook
ansible-playbook site.yml

# Install collection
ansible-galaxy collection install community.docker
```

## Scripts

- **00_quick_start.ps1** - Complete automated setup
- **01_set_ansible.sh** - Ansible installation/configuration

## 📚 Documentation

- **[Playbooks](playbooks/README.md)** - Essential playbooks
- **[Scripts](scripts/README.md)** - Example scripts
- **[Vault Guide](docs/ANSIBLE-VAULT-GUIDE.md)** - Password encryption
- **[Deployment Guide](docs/SECURE-DEPLOYMENT-GUIDE.md)** - Secure configurations


