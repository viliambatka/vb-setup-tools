# WSL scheduled tasks


## Start WSL on Windows startup

Start WSL using Windows Task Scheduler. The script uses `OracleLinux_8_10` as the default distro.

```powershell
# Start WSL when Windows starts.
# Run PowerShell as Administrator for Startup tasks.
.\01_set_start_wsl_task.ps1

# Replace an existing task
.\01_set_start_wsl_task.ps1 -force

# Custom distro and task name
.\01_set_start_wsl_task.ps1 -distroName "Ubuntu-22.04" -taskName "StartUbuntuWSL"

# Machine startup task running as SYSTEM
.\01_set_start_wsl_task.ps1 -triggerType Startup -RunAsSystem -force

# Start the user's WSL distro when the user logs on
.\01_set_start_wsl_task.ps1 -triggerType Logon -force
```
