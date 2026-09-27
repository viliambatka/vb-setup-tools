---
title: "WSL can't run Windows .exe files: 'Exec format error' with systemd=true"
date: 2026-09-26
updated: 2026-09-26
tags: [wsl, interop, systemd, binfmt]
status: draft
publish: no
---

**TL;DR:** In the `OracleLinux_9_5` distro, every Windows executable (`cmd.exe`, a Windows
venv's `python.exe`) fails with `Exec format error`. The `WSLInterop` handler is missing from
`binfmt_misc`. With `systemd=true` in `/etc/wsl.conf`, systemd resets `binfmt_misc` at boot and
wipes the entry WSL registered. **Fix not yet applied.**

## Symptoms

```text
/mnt/c/Windows/System32/cmd.exe: cannot execute binary file: Exec format error
.../kb_ai_agent/.venv/Scripts/python.exe: cannot execute binary file: Exec format error
```

Anything that shells out from WSL to Windows is affected: `cmd.exe`, `powershell.exe`,
`wsl.exe`, `explorer.exe`, and a Windows venv python called from a `.sh` script.

## Environment

- Distro `OracleLinux_9_5`, systemd as PID 1.
- `/etc/wsl.conf`, which does **not** disable interop:

  ```ini
  [network]
  generateResolvConf = false

  [boot]
  systemd=true
  ```

## Root cause

WSL runs Windows executables through a `binfmt_misc` handler named `WSLInterop`, which hands
PE files (magic `MZ`) to `/init`. The check showed:

- `binfmt_misc` is mounted, but it contains only `register` and `status`: **no `WSLInterop`
  entry**.
- `WSL_INTEROP=/run/WSL/..._interop` is set and `/init` exists, so WSL's interop server is up.
  Only the kernel handler is missing.
- `systemd-binfmt.service` is inactive, and `/etc/binfmt.d/` is empty.

This matches the widely reported interaction between WSL and systemd: systemd (re)mounts
`binfmt_misc` during boot and drops the `WSLInterop` registration WSL made just before.
[unverified here: that systemd is what removes it, as opposed to the entry never being registered]

### Evidence (2026-09-26)

Test: [`scripts/diagnostics/check_interop.sh`](../../scripts/diagnostics/check_interop.sh) (WSL).

```text
--- binfmt_misc mounted?
binfmt_misc on /proc/sys/fs/binfmt_misc type binfmt_misc (rw,relatime)
--- binfmt_misc entries
register
status
--- WSLInterop entry
(no WSLInterop entry)
--- systemd PID 1?
systemd
--- systemd-binfmt
inactive
--- WSL_INTEROP / WSL_DISTRO_NAME
WSL_INTEROP=/run/WSL/1218_interop WSL_DISTRO_NAME=OracleLinux_9_5
--- try cmd.exe
/mnt/c/Windows/System32/cmd.exe: cannot execute binary file: Exec format error
```

## Fix

**Not applied yet.** It changes the distro, which is also the CI runner host. The standard fix
is to make systemd re-register the handler on every boot:

```bash
# WSL, as root
echo ':WSLInterop:M::MZ::/init:PF' | sudo tee /etc/binfmt.d/WSLInterop.conf
sudo systemctl restart systemd-binfmt
```

**Rollback:** `sudo rm /etc/binfmt.d/WSLInterop.conf`, then restart the distro.

## Verification

`bash vb-setup-tools/scripts/diagnostics/check_interop.sh` shows a `WSLInterop` entry
(`enabled`, `interpreter /init`, `magic 4d5a`), and `cmd.exe /c ver` prints the Windows
version. Both must still hold after `wsl --terminate OracleLinux_9_5` and a restart.

## What didn't work

- **Assuming interop just works:** `wsl-to-host.md` and the repo AGENTS.md described
  "WSL script calls a Windows `.exe`" as a working pattern. It had never been tested here.
  The first real run of `scripts/diagnostics/probe_kb_retrieval.sh` *(vb-ai repo)* hit this
  error.

## Open questions

- [ ] Apply the fix, or design around interop (run Windows tools from PowerShell only)?
- [ ] Did interop ever work in this distro, for example before `systemd=true` was set?

## Findings log

- **2026-09-26:** found by the smoke test of the moved KB-retrieval probe; diagnosed with
  `check_interop.sh`.

## Before publishing

- [ ] apply and verify the fix; `status: verified`
- [ ] generalize distro name and paths
- [ ] set `publish: yes`
