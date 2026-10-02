# Ansible Playbooks

Simple playbooks for common tasks and Windows management.

## - Core Playbooks

### patch-systems.yml
Updates all packages on target systems.

```bash
ansible-playbook ansible/playbooks/patch-systems.yml
```

### setup-local-dev.yml  
Installs development tools (git, python, nodejs).

```bash
ansible-playbook ansible/playbooks/setup-local-dev.yml
```

### execute-script.yml
Runs local script on remote machines.

```bash
ansible-playbook ansible/playbooks/execute-script.yml -e "script_path=./ansible/scripts/system-info.sh"
```

## 🪟 Windows Management

VS Code portable install is a standalone script, not a playbook — see
[`../scripts/install-vscode-portable.sh`](../scripts/readme.md).

## Examples

```bash
# Target specific group
ansible-playbook patch-systems.yml -e "target_group=webservers"

# Prompt for sudo
ansible-playbook setup-local-dev.yml --ask-become-pass

# Script with arguments
ansible-playbook execute-script.yml -e "script_path=./scripts/deploy.sh" -e "script_args='--env prod'"
```
