# Observability runbook (alerting, log tail, SLOs)

## Polling worker design

Today alerting is foreground-only: `AlertWatch` diffs firing alerts +
failed CI runs on every auto-refresh while the app is open, and
`MetricsHistory` appends one point per successful poll (cap 120) to power
the latency chart + p95 KPI. True push while the app is closed still needs
`flutter_local_notifications` + `workmanager` — that is the open next step,
deliberately not added here (new plugins = store-review + permission work
for the owner).

The policy the future worker will run is already implemented and tested in
`lib/services/polling_alerts.dart`:

- `PollPolicy` — base 5 min, exponential backoff on consecutive failures,
  capped at 1 h. The worker stores only the failure streak.
- `Thresholds` — warn at 0.85, critical at 0.95 on cpu/ram/disk (0..1).
- `Slo.uptimePct` / `breaches` — uptime fraction over a poll window and
  the 0.99-target breach check (empty windows never breach).
- `NotificationHook.build` — `{title, body}` payload, max 3 items plus an
  "…and N more" overflow line, decoupled from model classes so both the
  snack bar today and push tomorrow consume the same shape.

## Notification hooks

1. Foreground (live): `AlertWatch.currentKeys` vs last-seen set →
   badge the bell + snack the `freshTitles` (max 3).
2. Future background: same `freshTitles` through `NotificationHook.build`
   into a local notification. No new payload format needed.

## Log tail

`LogTailService.fetch` reads over the existing SSH session — no agent
changes required. Sources are allowlisted and read-only:

| Source | Command | Notes |
|---|---|---|
| `journal` (default) | `journalctl --no-pager -n <20..500>` | falls back to `sudo -n` variant |
| `syslog` | `tail` of syslog/messages, else journal | `sudo -n` first, plain second |
| `docker` | `docker logs --tail=<n> <name>` | container name sanitized |

Parsing (`LogTailService.parse`) never throws: level is guessed
(ERROR/WARN/DEBUG/INFO) and over-long lines truncate at 300 chars.

## Uptime / p95 SLOs

- Uptime: `Slo.uptimePct(successes, total)` per host over the poll window;
  alert when `Slo.breaches(uptime, 0.99)`.
- Latency p95: `MetricsHistory.p95` over the stored series (ms), shown via
  `MetricsHistory.formatMs`. p95 > 1000 ms sustained across 3 polls =
  investigate (host overloaded or link degraded), not page.
- Targets are starting points, not SLAs: tune per host after a week of data.

## Agent-output alert evaluation (for the polling job)

`lib/services/alert_rules.dart` maps one `HostSignals` snapshot to
`AlertEntry` hooks — same threshold table as the SSH collectors in
`AgentService.fetchAlerts` (disk 80/90%, failed units, brute-force
5/20, load vs nproc, kernel/OOM, reboot < 1h), but evaluated over data
already harvested from the agent's HTTP endpoints. Pure Dart, no SSH,
no plugins — feed it once per poll tick per host:

- `/metrics` → disk ratio (per-mount detail still needs the SSH `df`
  collector until the agent exposes mounts; pass what you have).
- `/sysstats` (v4+) → `load1` + `nproc`, `boot_epoch_s` → uptime.
- SSH collectors → `failedUnits`, `failedLogins24h`, `kernelLines`.

Unknown signals stay at their defaults and skip their rule — a partial
snapshot never fires spuriously.

## When paged (any critical)

1. `curl -s http://<host>:9108/metrics` — agent alive?
2. No → `systemctl status mcp-agent`, `journalctl -u mcp-agent -n 50`
   (fix path: `docs/runbooks/agent-lifecycle.md`, incl. `--rollback`).
3. Yes → tail logs (`journal` source, then `docker` for the suspect
   container), check failed units (`systemctl --failed`).
4. Record the incident shape (which threshold, how long) before closing —
   that is the data that retunes the thresholds above.
