# mcpoll scheduler examples (Lisa, TM-1 follow-up)

Operator-owned scheduler templates for the standalone poller CLI
(`bin/mcpoll.dart`). These are **examples for interactive/operator use** —
they are NOT the managed app lifecycle (Zara owns lifecycle/verify/ledger
on top of `scripts/headless/`; Elizabeth owns the slice integration that
calls the in-app rail).

## Build + servers file

```sh
dart compile exe bin/mcpoll.dart -o ~/.local/share/mycontrolpanel/mcpoll
printf '[{"id":"web","name":"web","host":"192.168.1.10"}]' \
  > ~/.local/share/mycontrolpanel/servers.json
```

Servers file entries: `{id, name, host, port?, tokenEnv?}` — routable
facts only, never credentials. Per-host agent tokens resolve from the
environment (`tokenEnv` names the variable, default `MCP_AGENT_TOKEN`).

## Scheduled vs interactive runs

- **Scheduled runs** (these templates) target agents that need no token:
  argv carries host names and file paths only, and the unit/task files
  contain no environment secrets (ADR-003 invariant — pinned by
  `test/mcpoll_test.dart`).
- **Interactive runs** needing a token pass it via the process
  environment, e.g. `MCP_AGENT_TOKEN=... mcpoll --consent --host H`
  (single-host mode), or per-host variables named by each entry's
  `tokenEnv`. Tokens never appear on argv, in files, or in logs.

## Install

```sh
./scripts/mcpoll/install-linux.sh [install-dir]      # systemd user timer
./scripts/mcpoll/install-macos.sh [install-dir]      # LaunchAgent
.\scripts\mcpoll\install-windows.ps1 [-InstallDir …]  # Task Scheduler
```

Removal: `systemctl --user disable --now mcp-poll.timer` (+ delete the two
unit files), `launchctl unload ~/Library/LaunchAgents/com.mycontrolpanel.mcpoll.plist`
(+ delete), `schtasks /Delete /TN '\MyControlPanel\mcpoll' /F`.

## Exit codes / output

Same frozen table as the app rail: `0` tick ok, `2` skipped (no
`--consent`, lock held, backoff active), `1` error. Stdout is the versioned
JSON tick line (titles only). Full operator guide:
`docs/runbooks/mcpoll.md`.
