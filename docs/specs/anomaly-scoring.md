# Adaptive anomaly scoring (Farah — ML)

On-device, per-metric anomaly scoring that replaces static thresholds
with baselines that learn the server's normal. Ships in two stacked PRs:
agent + eval harness (PR 1/2), Flutter picker + docs (PR 2/2, this doc).

## What

`GET /anomaly?metric=cpu&value=0.42&hour=14&sensitivity=medium`
→ `{"version":6,"metric":"cpu","value":0.42,"sensitivity":"medium",
"hour":14,"score":78.0,"reason":"0.87 vs usual 0.31 at 14:00 (score 78)",
"firing":true,"z":4.4,"baseline":0.31}`.

- `score` 0..100 is sensitivity-independent (deviation magnitude).
- `firing` applies the sensitivity gate. `reason` is the
  why-this-alerted copy shown in the alert rail.

## Algorithm (stdlib only, both sides)

EWMA mean + rolling residual variance, plus 24 hourly time-of-day
buckets (Welford). Each sample is scored against the *prior* baseline,
then observed — a spike never contaminates its own verdict. A 2%
variance floor keeps exactly-flat baselines (a disk ratio unchanged for
days) sensitive instead of dividing by zero.

| Sensitivity | z to fire | min score | behaviour |
|---|---|---|---|
| Low | ≥ 4.0 | ≥ 70 | rare, high-confidence alerts only |
| Medium (default) | ≥ 3.0 | ≥ 50 | balanced |
| High | ≥ 2.0 | ≥ 30 | catch everything, expect noise |

Canonical source: `agent/anomaly_scorer.py`. The deployed agent embeds
it verbatim in `AgentService.agentScript` (`agent/revendor.py` re-syncs;
`test/agent_embedded_parity_test.dart` fails on drift). The app-side
companion (`lib/services/anomaly_scoring.dart`) mirrors the tiers, parses
`/anomaly` payloads (`AnomalyScore.parse`, null on pre-v6), and builds
the shared why-copy (`anomalyWhyCopy`).

## Offline eval (gates for TM-5)

`python -m pytest agent/tests -q` — deterministic synthetic traces, no
RNG, no I/O. Measured on this branch:

- ops-day trace (diurnal + 10 spikes + 1 sustained shift, 1440 1-min
  samples): **precision 0.95** (gate > 0.85), event recall 0.91.
- idle device-day (flat + jitter, zero incidents): **0 false alerts**
  at Medium (gate < 1).
- cost **≈0.006 ms/sample**; a full idle day scores in milliseconds —
  far below the 1% CPU budget at a 60 s poll cadence.

## App wiring (reuses #116/#117/#118 — no new rails)

- One shared pref (`anomaly_sensitivity`, default Medium) + Settings
  segmented picker next to the background-alerts consent row.
- `AlertPipeline(sensitivity:)` labels cpu-anomaly titles with the
  why-copy (`CPU anomaly on X — CPU 95% vs usual 30% · score 3.9
  (Medium)`); titles still flow through the existing
  `NotificationHook.build` funnels on mobile (#116), desktop (#117),
  and snack bar. The stale-state line (#118) is untouched.
- `AgentService.fetchAnomaly(...)` (null on pre-v6/unreachable — caller
  falls back to local detectors, never crashes the rail).

## Privacy (binding wording, also shown under the picker)

Fully on-device: baselines live in the agent's process memory on the
user's own server, computed from their own metrics. Nothing leaves the
user's infrastructure — no cloud, no telemetry, no new permissions.

## Handoff to Nadia (AI/ML Ops)

- **Deploy:** v6 is additive (`/anomaly` only; `/metrics`, `/procstats`,
  `/sysstats`, `/health`, `/logs`, `/cronruns` unchanged). Old app +
  new agent and new app + old agent both work (parse returns null on
  pre-v6 → local-detector fallback). Roll out via the normal one-click
  reinstall (rotates the agent token as before); no migration, no config.
- **Operate:** baselines are in-memory — an agent restart re-warms
  (15 samples, `learning baseline (n/15)` verdicts, no alerts while
  warming). Nothing to back up, nothing to monitor beyond the existing
  `:9108 /health` check.
- **Integrate (for Zara's poll loop, 3 lines):** load the picker value
  (`await AnomalyScoringPrefs.load()`), score the fresh sample
  (`await agent.fetchAnomaly(host, value: cpu, hour: DateTime.now().hour,
  sensitivity: sens, serverId: id)`), and route a non-null `firing`
  result into the existing `NotificationHook.build` funnel with
  `score.alertTitle` — same dedupe/cooldown/staleness contracts as today.
- **Rollback:** reinstall the v5 agent (previous `agentScript`); the app
  keeps working on local detectors. No data to clean up.
- **Do not:** put scorer state on disk, add non-stdlib deps to the
  agent, or send scores anywhere off-host — the privacy note above is a
  release-level promise (Burhanah's gate C6 pins it via this file).
