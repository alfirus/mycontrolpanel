# mcpoll operator runbook (Lisa, TM-1 follow-up)

Standalone headless poller CLI: `bin/mcpoll.dart`. Polls agent `:9108`
endpoints from machines (or contexts) where the app vault/prefs are
unavailable — CI boxes, jump hosts, cron-style watchers — and reports
through the same frozen headless pipeline as the app rail.

Seam note: the in-app closed-app slice + tray integration is Elizabeth's
(`t_a0fe4895`) and calls the in-app rail (`--poll-headless`); mcpoll is
the operator rail and never replaces it.

## Build

```sh
# Ad-hoc (plain Dart, no UI, no plugins):
dart run my_control_panel:mcpoll --consent --host 192.168.1.10 --name web

# Scheduled (compile once, then point the OS at the binary):
dart compile exe bin/mcpoll.dart -o ~/.local/share/mycontrolpanel/mcpoll
```

## Servers file

JSON array of `{id, name, host, port?, tokenEnv?}` — routable facts only,
never credentials:

```json
[
  {"id": "web", "name": "web", "host": "192.168.1.10"},
  {"id": "db", "name": "db", "host": "192.168.1.11", "port": 9108, "tokenEnv": "MCP_AGENT_TOKEN_DB"}
]
```

Tokens resolve from the environment at fetch time (`tokenEnv` names the
variable, default `MCP_AGENT_TOKEN`). Scheduled runs target agents that
need no token; interactive runs export the variable first. Tokens never
appear on argv, in files, or in logs/stdout.

## Consent, state, locking

- `--consent` is required to poll (per-invocation operator consent).
  Without it the tick exits `2` with a JSON `skipped` line, touching
  nothing — the analogue of the app's `background_alerts` pref gate.
- State lives in the shared `headless_state.json` (+ `headless.lock`)
  resolved exactly like the app rail: `--state-dir` →
  `$MCP_STATE_DIR` → per-user default. Point mcpoll at the same dir and
  the two rails share transition-only dedup + backoff + single-flight.
- Every exit path (ok / skipped / error) updates `lastCheckMs`, so a
  "last checked" reader stays honest with the window closed.

## Transport

Per host (default 15 s timeout, max 10 hosts — frozen parity with the app
rail): `GET /alerts/snapshot` first (pre-snapshot agents answer 404 →
automatic fallback to the `GET /metrics` + `GET /sysstats` pair). One sick
host never sinks the run; total failure exits `1` with a consecutive-
failure streak increment (same `PollPolicy` backoff: base 5 min → cap
1 h). The SSH sweep (failed units, brute force, kernel, fine mounts)
stays in the app's `pollHostAlerts` — mcpoll is the agent-HTTP rail.

Verdicts reuse the frozen table verbatim: `AlertRules` 80/90 disk,
`Thresholds` 0.85/0.95 cpu/ram gauges (metrics leg only — the snapshot
carries no cpu/ram by design), `NotificationHook.build` title
`'MyControlPanel alert'`, `kind::owner::title` dedup, 6 h resend cooldown.

`--no-snapshot` forces the legacy pair (compat check against old agents).

## Exit codes / output

`0` tick ok (`ok` / `notified`), `2` skipped (no `--consent`, lock held,
backoff active, nothing answered on a skipped path), `1` error (bad argv,
total transport failure, pre-evaluation crash). Stdout is one JSON line
with the frozen shape (`version`, `status`, `exitCode`, `checkedAtMs`,
`freshTitles`, `notification?`, `reason?`) — titles only, never secrets.

## Schedulers

Per-user operator examples in `scripts/mcpoll/` (Windows Task Scheduler
XML, systemd user service + timer, macOS LaunchAgent, install scripts).
They invoke `mcpoll --consent --servers …` with no credential material
anywhere in the artifact (pinned by `test/mcpoll_test.dart`). Managed
lifecycle (verify/status/ledger) is Zara's lane on top of
`scripts/headless/` — these examples intentionally duplicate none of it.
