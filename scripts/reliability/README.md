# Alert reliability — hardened scheduler templates (Nadia, operability)

Drop-in hardened variants of the TM-1 minimal templates
(`scripts/headless/`, Lina owns the argv contract). Same scheduler
argv (`mycontrolpanel[.exe] --poll-headless`, exact — never add flags),
same per-user / no-elevation scope, same vault-only reads inside the
process (ADR-003). The hardening is restart/backoff + log routing only.

## What changes vs the minimal templates

| OS | File | Hardening |
|---|---|---|
| Linux | `linux/mcp-poll.hardened.service` + `.timer` | `Restart=on-failure` + `RestartSec=60` (exit 1 retries; 0/2 pinned clean via `SuccessExitStatus`), `StartLimit*` burst cap, tick stdout/stderr appended to the per-user tick log |
| Windows | `windows/mcp-poll-task.hardened.xml` | `RestartOnFailure` (3 × 5 min), `ExecutionTimeLimit` PT5M, `StartWhenAvailable` + `RunOnlyIfNetworkAvailable` |
| macOS | `macos/com.mycontrolpanel.poll.hardened.plist` | `KeepAlive.SuccessfulExit=false` (relaunch on crash only), `ThrottleInterval=60` backoff |

## Log rotation

The delivery log (`delivery.log`, JSONL) is size-capped by policy
(`AlertLogRotation`: 512 KiB per generation, base + `.1` + `.2`):

```sh
# check (prints rotationDue in the JSON report)
dart run my_control_panel:agent_check --check --json --log <path>/delivery.log
# rotate when due (safe mid-window: --check reads all live generations)
dart run my_control_panel:agent_check --rotate --log <path>/delivery.log
```

Wire `--rotate` as a weekly companion task/timer alongside the poll
schedule, or run it from the same install script that drops these
templates.

## Ownership

- argv contract + minimal templates: Lina (TM-1).
- These hardened variants: Nadia (operability).
- Managed lifecycle (verify/status/ledger from these templates): Zara.
- Security review (scope, elevation, credential handling): Alya.
- QA matrices + Beta.2 gate: Balqis (evidence: `agent_check` JSON).
