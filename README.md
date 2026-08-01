# VB-Tools - V1.0

Automation tools for Windows development: WSL, WebLogic, Ansible.


## Quick Start

```powershell
# Complete setup
.\00_quick_start.ps1

# Explicit complete setup
.\00_quick_start.ps1 -All

# Clean/reset supported components before setup
.\00_quick_start.ps1 -All -Clean

# Force reinstall/recreate behavior where supported
.\00_quick_start.ps1 -All -Force

# Selected components
.\00_quick_start.ps1 -Wsl -Docker -K8s

# WebLogic only, after downloading the required Oracle installers
.\00_quick_start.ps1 -WebLogic

# Custom WSL distribution
.\00_quick_start.ps1 -All -distroName "Ubuntu-22.04"

# Individual components
.\wsl\00_quick_start.ps1      # WSL
.\ansible\00_quick_start.ps1  # Ansible
.\weblogic\00_quick_start.ps1 # WebLogic
.\wslg\00_quick_start.ps1     # WSLg addition to WSL (must be executed manually) .. example for gvim 
```

NOTE: files are normalized in repo to LF line endings for consistency across platforms. please see [`.gitattributes`](.gitattributes)

## Components

- **[WSL](./wsl/readme.md)** - Windows Subsystem for Linux setup
- **[WebLogic](./weblogic/readme.md)** - Oracle WebLogic automation  
- **[Ansible](./ansible/readme.md)** - Infrastructure automation

## Examples

```bash
# Build sample app
cd weblogic/sample && mvn clean package
```

## delete WSL

```powershell
# List installed WSL distributions
wsl --list --verbose    
# Unregister (delete) a specific distribution
wsl --unregister <DistroName>
```

MIT License - see [LICENSE](LICENSE)

## Contributing

We welcome contributions to VB-Tools! Please follow these steps:

1. **Fork the Repository**: Create your own fork of the repository on GitHub.
2. **Create a Branch**: Create a new branch for your feature or bug fix.
3. **Make Changes**: Make your changes in the new branch.
4. **Test Your Changes**: Ensure that your changes work as expected.
5. **Submit a Pull Request**: Submit a pull request to the main repository.

Thank you for your contributions!
