# Headless poll — manual install / uninstall (TM-1, Lina)

Manual dogfood path for the `--poll-headless` tick. The managed lifecycle
(verify/status/run ledger) is Zara's ops runbook
(`docs/runbooks/background-alerting-ops.md`, t_13eee02b) — this page covers
only: install it by hand, prove one tick, remove it again.

Contract reference: `docs/specs/headless-cli-contract.md`.
Exit codes: `0` tick ok · `2` skipped (consent OFF / vault locked /
backoff) · `1` error.

## Prerequisites (all OSes)

1. Install the app, open it once, add at least one server.
2. Settings → background alerts toggle ON (default OFF — the headless tick
   honors the shared `background_alerts` pref and exits `2` when OFF).
3. If the Biometrics app-lock toggle is ON, the headless tick treats the
   vault as locked and exits `2` by design (no headless prompt). Turn it
   OFF on a machine you want headless polling on, or accept skips.

## Prove one tick by hand (no scheduler)

Run the installed binary directly and read the JSON line:

- Windows: `"C:\Users\<you>\AppData\Local\MyControlPanel\mycontrolpanel.exe" --poll-headless`
- Linux: `~/.local/share/mycontrolpanel/mycontrolpanel --poll-headless`
- macOS: `/Applications/MyControlPanel.app/Contents/MacOS/mycontrolpanel --poll-headless`

Expect one JSON line, e.g.
`{"version":1,"status":"ok","exitCode":0,...}`. First firing run reports
`"status":"notified"` + the toast; an immediate re-run reports
`"status":"ok"` (transition-only — no double toast).

State lives next to the install (see contract §4): `headless_state.json`
(seen-set + streak) and `headless.lock` (single-flight). Deleting the
state file resets dedup (next firing tick notifies once).

## Install (per-user, no elevation)

Windows (non-elevated PowerShell, from the repo):

```powershell
.\scripts\headless\install-windows.ps1 -InstallDir "$env:LOCALAPPDATA\MyControlPanel"
schtasks /Query /TN "\MyControlPanel\poll-headless"
```

Linux:

```sh
./scripts/headless/install-linux.sh ~/.local/share/mycontrolpanel
systemctl --user status mcp-poll.timer
```

macOS:

```sh
./scripts/headless/install-macos.sh /Applications/MyControlPanel.app/Contents/MacOS
launchctl print "gui/$(id -u)/com.mycontrolpanel.poll"
```

## Uninstall

```powershell
.\scripts\headless\uninstall-windows.ps1
```

```sh
./scripts/headless/uninstall-linux.sh
./scripts/headless/uninstall-macos.sh
```

Uninstall removes the scheduler artifact only. To also clear headless
state, delete the per-user state dir (contract §4). Server list, vault
entries, and prefs are never touched by install or uninstall.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `exitCode: 2`, "consent OFF" | toggle OFF | Settings → background alerts ON |
| `exitCode: 2`, "vault locked" | app lock ON / keychain unavailable | turn Biometrics OFF, or accept skips |
| `exitCode: 2`, "backoff active" | repeated transport failures | check host reachability; streak resets on next success |
| `exitCode: 2`, "already running" | slow previous tick (long SSH) | benign — next interval runs normally |
| `exitCode: 1`, "argv carries forbidden material" | tampered scheduler artifact | reinstall via the scripts above; escalate to Alya |
| `exitCode: 1`, "both down" | agent :9108 + SSH unreachable | check network / agent on the host |
| Toast on every tick | state file deleted or unwritable | check state-dir permissions (per-user, writable) |
| No toast, `status: ok` | steady firing state (by design) | resolve + re-fire to test the transition |

Security notes: scheduler argv carries no token, key path, or passphrase
— credentials are read from the OS vault inside the tick (ADR-003). Never
append `--token=`-style args; the tick self-rejects them with exit `1`.
