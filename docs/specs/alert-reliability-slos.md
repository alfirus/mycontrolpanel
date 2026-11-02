# Alert reliability SLOs (Beta.2 — Nadia, MLOps)

Owner: Nadia. Consumers: headless tick (TM-1), in-app `AlertPollJob`,
`agent_check --check` (operability companion), opt-in SLO dashboard.
Binding thresholds: `AlertSlo` in `lib/services/alert_reliability.dart`
is the machine-readable freeze — this doc explains intent; the class
decides. Changes need Rina sign-off (same freeze rule as the TM-1
contract: risk 2 in `docs/project/tray-mode-plan.md`).

## 1. Lifecycle under measurement

Every firing signal moves through four stages; each transition is
timestamped in the delivery log (JSONL, one `AlertDeliveryRecord`
per line):

```text
scheduled → executed → notified → dismissed
   (tick)    (gates)     (rail)      (user)
```

- **scheduled**: a poll tick produced the signal (headless or in-app).
  Identity reuses `AlertWatch.keyFor` (`kind::owner::title`) verbatim —
  one dedup contract, never a second id scheme.
- **executed**: the signal passed the gates (consent ON, vault
  unlocked, backoff clear, transport answered) and reached fan-out.
- **notified**: the OS rail accepted the `NotificationHook.build`
  payload (`{title, body}`, max 3 + "…and N more").
- **dismissed**: the user acted on or cleared the signal.

A row that never reaches `notified` within the delivery window is a
**drop** (transport died, rail rejected, process killed) — counted,
never silent.

## 2. The four SLOs

| # | SLO | Threshold | Measured over |
|---|---|---|---|
| S1 | Delivery | 99% of scheduled signals notified **within 5 min** | delivery-log window |
| S2 | Drops | **<1%** of scheduled signals never notified | rows older than 5 min |
| S3 | Tick cost | **p95 < 2 s** poll-tick wall time | `tickDurationsMs` window |
| S4 | Agent footprint | **p95 < 50 MB** agent RSS | `resourceSamples` window |

Notes:

- S1 counts *in-window* notifies only: a signal notified at 5 min 1 s
  misses S1 but is **not** an S2 drop (it did arrive).
- S3 covers tick start → fan-out done, per host-tick; the 15 min
  scheduler cadence is the freshness bound, not the cost bound.
- S4 tracks the *metrics agent* (`:9108`, on-host RSS) alongside the
  headless tick so model-serving capacity regressions surface in the
  same report. Battery (mobile) is sampled best-effort for the
  dashboard; it carries no SLO — OS schedulers own that budget.
- Empty windows are healthy-with-null-rates, never breaches: a quiet
  fleet must not page.

## 3. How it is measured

1. The tick records transitions into `AlertReliabilityTracker`
   (in-memory) and appends the row to the JSONL delivery log.
2. `evaluateSlo(nowMs:)` computes rates + p95s and returns the breach
   list (`delivery`, `drops`, `tick-p95`, `agent-mem-p95`).
3. `agent_check --check --json` (operability companion) replays the
   JSONL log off-device-state and prints the same report as JSON —
   exit `0` healthy, `1` any breach, `2` skipped/no data. CI and the
   dashboard consume that JSON, never the raw log.
4. Log rotation (size-capped generations, see the operability spec)
   bounds disk use; rotation never rewrites history inside a window —
   `agent_check` reads all live generations.

## 4. Relationship to existing policy (reuse, verbatim)

| Concern | Source | Reused as |
|---|---|---|
| Poll backoff | `PollPolicy` | `executed` gate (backoff-active ⇒ skip, not a drop) |
| Thresholds | `AlertRules` / `Thresholds` | what counts as a firing signal |
| Payload | `NotificationHook.build` | what counts as `notified` |
| Dedup identity | `AlertWatch.keyFor` | delivery-log `id` |
| Uptime math style | `Slo` / `MetricsHistory.p95` | nearest-rank percentile convention |

No new payload formats, no remote push, no telemetry export: all
evaluation is on-device, and the dashboard (companion spec) is
local-only and opt-in.

## 5. Beta.2 gate reading

TM-6 (Balqis) closes when a soak window shows S1 ≥ 99%, S2 < 1%,
S3 p95 < 2 s, S4 p95 < 50 MB on Windows + Linux + macOS closed-app
runs. The `agent_check` JSON is the evidence artifact attached to
the gate.
