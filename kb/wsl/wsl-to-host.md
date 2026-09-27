---
title: "WSL can't reach Ollama on the Windows host: NAT vs mirrored networking"
date: 2026-09-26
updated: 2026-09-26
tags: [wsl, networking, nat, mirrored, dns, ollama, windows]
status: draft
publish: no
---

This is the single place for what is known about networking between the WSL distro
(`OracleLinux_9_5`) and the Windows host on this machine. Read it before running
another ad-hoc connectivity test, and add every new finding here with its date.

Legend: **[verified]** = observed on this machine (date given) · **[unverified]** =
a reasonable expectation that has not been tested here yet.

---

## TL;DR

| Question | Answer |
| --- | --- |
| Which WSL networking mode is in use? | **NAT** (`.wslconfig` has `networkingMode=mirrored` commented out). [verified 2026-09-26] |
| Does WSL reach the internet? | **Yes, in NAT.** [verified by user] |
| Does WSL reach Windows services via `localhost` / `127.0.0.1`? | **No, in NAT.** Inside WSL, `127.0.0.1` is the Linux VM itself, not Windows. |
| How do WSL-run tools get an Ollama at `localhost:11434`? | Run Ollama **inside WSL** with `scripts/start-ollama.sh` *(parent repo)*. It shares the Windows model store. |
| Can WSL start a Windows `.exe` (such as `python.exe`) at all? | **No, currently.** Interop is broken: `Exec format error`, because there is no `WSLInterop` binfmt entry under systemd. See [windows-exe-exec-format-error.md](windows-exe-exec-format-error.md). [verified 2026-09-26] Once fixed, such a process runs on the Windows network stack, so its `localhost` is Windows. |
| Why not use mirrored mode? | On this machine mirrored mode reaches the host but **not the internet**, or comes up with no working adapters at all. See [Mirrored mode](#mirrored-mode). |
| Where do `.sh` / `.ps1` scripts run? | `.sh` in WSL, `.ps1` in Windows PowerShell. See AGENTS.md *(parent repo)*. |

---

## Networking modes

### NAT (current)

- **Config:** `C:\Users\vilia\.wslconfig`:

  ```ini
  [wsl2]
  # networkingMode=mirrored  # disabled: not binding any host adapter (all eth* DOWN, no route) — falling back to NAT. Reconfirmed failing multiple times (2026-09-15/16).
  vmIdleTimeout=-1
  memory=32GB
  ```

- **Internet from WSL:** works. [verified by user]
- **Guest side:** a single `eth0` on `172.x`, with the default gateway at the Windows side
  of the WSL virtual switch. [02_diagnostics.ps1 describes this as the NAT signature]
- **Host services on `localhost`:** not reachable. `127.0.0.1` in WSL is the VM's own loopback.
- **Host services via the gateway IP**
  (`ip route show default | awk '{print $3}'`): only reachable if the Windows service
  listens on all interfaces (`0.0.0.0` / `::`, not just `127.0.0.1`) **and** Windows
  Firewall allows inbound traffic from the WSL virtual network. [unverified: see the
  test below]
- **From the LAN:** services running inside WSL are hidden behind NAT and are not
  reachable from other machines.

### Mirrored mode

The setup script [`add-ins/01_set_wslconfig.ps1`](../../wsl/add-ins/01_set_wslconfig.ps1) still
writes `networkingMode=mirrored` by default. [`02_diagnostics.ps1`](../../wsl/02_diagnostics.ps1)
still marks anything other than mirrored as WARN, because the project originally wanted
k8s and Ollama reachable on the LAN. **On this machine mirrored mode is currently not
usable.** Two failure variants have been seen:

1. **Host reachable, internet not reachable.** [verified by user]
2. **No connectivity at all:** every `eth*` DOWN, empty routing table, and the guest
   kernel log repeating:

   ```text
   hv_netvsc <GUID> ... unable to open channel: -19   (-ENODEV)
   hv_vmbus:  probe failed for device <GUID> (-19)
   ```

   The host offers a netvsc VMBus channel that it cannot back. `wsl --shutdown` does
   **not** clear this; only a full Windows reboot did. Reconfirmed failing 2026-09-15/16.
   Details and a read-only checker: [`02_diagnostics.ps1`](../../wsl/02_diagnostics.ps1)
   (run it **before** rebooting, because the reboot destroys the evidence).
   - A lone `-ENODEV` **with** a working default route is normal and harmless: one
     virtual adapter (WAN Miniport, disconnected Wi-Fi) can't be mirrored. It is a
     failure only when there is also no default route.

### DNS

- `/etc/resolv.conf` in WSL is **configured as expected**. [verified by user]
- It is managed by [`add-ins/02_set_dns.sh`](../../wsl/add-ins/02_set_dns.sh), which sets
  `generateResolvConf = false` in `/etc/wsl.conf` and writes explicit `nameserver` lines
  (the original is backed up to `/etc/resolv.conf.bak`).
- DNS is independent of the networking mode. A correct `resolv.conf` does **not** prove a
  route exists: "DNS resolves but curl error 7 (couldn't connect)" means there is no
  route, not a DNS problem.

---

## Ollama: which server does what

There can be **up to three** Ollama servers on port `11434`. Know which one a tool talks to.

| Server | How it starts | Listens on | Who reaches it |
| --- | --- | --- | --- |
| Windows Ollama (tray app / default) | Ollama app, or `ollama serve` with no `OLLAMA_HOST` | `127.0.0.1:11434` | Windows processes only, including a Windows `.exe` started from WSL |
| Windows Ollama (exposed) | `scripts/start-ollama.ps1` *(parent repo)* sets `OLLAMA_HOST=0.0.0.0` | all interfaces | Windows; WSL via the gateway IP **if the firewall allows it** [unverified] |
| WSL-native Ollama | `scripts/start-ollama.sh` *(parent repo)*, or the `ollama` systemd service in WSL | WSL `localhost:11434` | WSL processes (`run.sh`, the agent loop, WSL `.venv/bin/python`) |

- **Model store is shared.** The WSL Ollama uses `OLLAMA_MODELS=/mnt/j/ollama_models`,
  the same store as the Windows Ollama (`J:\ollama_models`), so models are not downloaded
  twice. **Never pull from both servers at the same time**, because concurrent writes to
  the blob store risk corruption. Concurrent reads for inference are fine.
- **GPU:** passthrough works in WSL (`nvidia-smi` visible), so the WSL Ollama uses the GPU.
  All servers share **one 12 GB GPU**, so running several at once makes them compete for
  VRAM and unload each other's models.
- **Which tool uses which server:**

  | Tool | Runs as | Ollama URL | Reaches |
  | --- | --- | --- | --- |
  | `run.sh`, agent loop (`configs/agent.toml` *(parent repo)* `host = "http://localhost:11434"`) | WSL | `localhost:11434` | WSL-native Ollama |
  | `vb-ai/kb_ai_agent/01_index_kb.ps1`, `02_query_agent.ps1` | Windows | `OLLAMA_BASE_URL` in the env file (default `http://localhost:11434`) | Windows Ollama |
  | `scripts/diagnostics/probe_kb_retrieval.sh` *(vb-ai repo)* | started in WSL, runs the **Windows** `kb_ai_agent/.venv/Scripts/python.exe` | `localhost:11434` | **fails today** (interop broken, see above); would reach the Windows Ollama |

### Observed 2026-09-26 (from Windows)

```text
Get-NetTCPConnection -LocalPort 11434 -State Listen
LocalAddress  OwningProcess  (ollama.exe, started)
::            24308          20:30:39
127.0.0.1     43256          20:30:07
```

- **Two Windows `ollama.exe` servers on the same port:** one on loopback and one on all
  interfaces (`::`).
- `OLLAMA_HOST` is not set at User or Machine level. The all-interfaces one was probably
  started with a per-process `OLLAMA_HOST`, for example by `start-ollama.ps1` or the Ollama
  app's "expose to network" setting. [unverified]
- Requests to `127.0.0.1` from Windows go to the loopback one. Requests to the host IP
  go to the `::` one. **They do not share loaded models or VRAM budget.**
- A WSL-native Ollama, if running, would not show up in this Windows list.

---

## Crossing the boundary from WSL scripts

- **Windows `.exe` called from WSL** (interop): **broken in this distro today**; see
  [windows-exe-exec-format-error.md](windows-exe-exec-format-error.md). When it works, it runs
  on the Windows side:
  - Convert path arguments with `wslpath -w` (`/mnt/j/x` → `J:\x`). The `.exe` cannot
    open `/mnt/...` paths.
  - WSL environment variables reach the `.exe` **only** if listed in `WSLENV`. Pass
    settings as arguments instead.
  - For networking, the `.exe` uses Windows' stack, so `localhost` means Windows.
- **Windows → WSL:** in NAT mode, Windows `localhost:<port>` is forwarded to services
  listening inside WSL (WSL's localhost forwarding). [unverified here]

---

## Tests

Run each test and note the result, with the date, in the [Findings log](#findings-log).

### From WSL: which Ollama can I reach?

```bash
GW=$(ip route show default | awk '{print $3}')
echo "default gw: $GW"
curl -s -m 5 http://127.0.0.1:11434/api/version || echo "127.0.0.1 : unreachable (NAT: fine if no WSL-native Ollama runs)"
curl -s -m 5 "http://$GW:11434/api/version"   || echo "$GW : unreachable (firewall, or no Windows Ollama on all interfaces)"
curl -s -m 5 https://ollama.com >/dev/null && echo "internet: OK" || echo "internet: FAIL"
systemctl is-active ollama 2>/dev/null; pgrep -a ollama || echo "no WSL-native ollama process"
```

### From WSL: networking mode and DNS

```bash
ip -br addr; ip route; ip rule | head
cat /etc/wsl.conf; cat /etc/resolv.conf
getent hosts ollama.com
```

A NAT signature is a single `eth0` on `172.x` with no per-interface `ip rule` entries.
Mirrored mode shows the host LAN address and per-interface rules.

### From Windows (PowerShell): who listens on 11434?

```powershell
Get-NetTCPConnection -LocalPort 11434 -State Listen | ForEach-Object {
  $p = Get-Process -Id $_.OwningProcess
  [pscustomobject]@{ Address = $_.LocalAddress; Pid = $p.Id; Name = $p.ProcessName; Started = $p.StartTime }
}
Get-NetFirewallRule -DisplayName "*ollama*" -ErrorAction SilentlyContinue | Select-Object DisplayName,Enabled,Direction,Action,Profile
```

### Full diagnostics

- Windows + guest, mirrored-mode focused: `vb-setup-tools\wsl\02_diagnostics.ps1` (PowerShell)
- Runner / distro / Ollama from the distro: `scripts/diagnostics/01_check_wsl_runner_health.sh` *(parent repo)*
- Interpreter / venv / Ollama for `run.sh`: `scripts/diagnostics/07_check_python_env.sh` *(parent repo)*

---

## Open questions

- [ ] Does WSL reach the Windows `::` Ollama through the gateway IP, or does Windows Firewall
      block it? (Run the first test above.)
- [ ] Who starts the second Windows Ollama (`::`, PID 24308 on 2026-09-26)? Is it wanted?
- [ ] Should there be exactly one Ollama? For example, the WSL-native one for the loop plus the
      Windows loopback one for kb_ai_agent, with the exposed Windows one stopped.
- [ ] Mirrored mode "host OK, internet not": is it a routing issue (default route on the wrong
      mirrored NIC) or DNS? Capture `ip route`, `ip rule` and `getent hosts` next time it
      happens.
- [ ] `add-ins/01_set_wslconfig.ps1` and `02_diagnostics.ps1` still treat mirrored as the target.
      Either update them to NAT or keep the WARN as a reminder.

---

## Findings log

Add new findings at the top, with the date and who or what observed them.

- **2026-09-26:** WSL → Windows `.exe` interop is broken (`Exec format error`, no `WSLInterop`
  binfmt entry, `systemd=true`). Details: [windows-exe-exec-format-error.md](windows-exe-exec-format-error.md).

- **2026-09-26:** NAT confirmed in `.wslconfig`. Internet works from WSL in NAT. In mirrored
  mode the host was reachable but the internet was not. `resolv.conf` is as expected (user).
  Two Windows `ollama.exe` were listening on 11434 (`127.0.0.1` PID 43256, `::` PID 24308).
  `OLLAMA_HOST` is unset at User/Machine level.
- **2026-09-15/16:** mirrored mode failed repeatedly with no host adapter bound (all `eth*`
  DOWN, no route, netvsc `-ENODEV`). Fell back to NAT (`.wslconfig` comment,
  `start-ollama.sh` header).

---

## Before publishing

- [ ] no secrets, tokens, internal hostnames or IPs
- [ ] personal paths generalized (`J:\...`, `C:\Users\vilia`, `/mnt/j/...`, PIDs)
- [ ] repo-internal links replaced or explained for outside readers
- [ ] resolve the open questions (or state them as open) and set `status: verified`
- [ ] set `publish: yes`
