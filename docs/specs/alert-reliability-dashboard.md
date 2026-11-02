# SLO dashboard spec — local-only, opt-in (Beta.2 — Nadia)

Owner: Nadia. Implements the *view* half of
`docs/specs/alert-reliability-slos.md`; the *measure* half
(`AlertReliabilityTracker`, `agent_check --check`) already exists.
**Spec only — no UI code in this PR** (widgets land with the tray
shell, TM-4, against this contract).

## 1. Non-goals (binding)

- **Local-only**: the dashboard reads the on-device delivery log and
  tick stats. No network fetch, no telemetry export, no account, no
  analytics SDK. A packet capture during dashboard use shows zero new
  egress — Balqis pins this in the QA matrix.
- **Opt-in**: the dashboard surface is gated behind the SAME shared
  `background_alerts` pref (default OFF) — no second toggle. Consent
  OFF ⇒ the dashboard shows the consent explainer, never stale numbers
  presented as live.
- **No new payload formats**: cards render `NotificationHook.build`
  titles and `AlertSloReport` rates only.

## 2. Surface

Settings → **Reliability** row (visible always; content gated):

- Consent OFF: `BackgroundAlerts.consentCopy` + a link to the toggle.
  No charts, no history.
- Consent ON: four SLO cards + a staleness line.

### SLO cards (one per SLO, same order everywhere)

| Card | Green | Amber (watch) | Red (breach) | Drill-down |
|---|---|---|---|---|
| Delivery S1 | ≥99% in 5 min | 97–99% | <97% | worst-10 late signals (titles only) |
| Drops S2 | 0% | — | ≥1% | dropped signal titles + transport leg |
| Tick cost S3 | p95 <2 s | 2–5 s | ≥5 s | per-tick sparkline (last 120, `MetricsHistory` cap) |
| Agent S4 | p95 <50 MB | 50–100 MB | ≥100 MB | RSS sparkline + battery note (mobile) |

- Numbers come from `agent_check`-equivalent evaluation over the same
  JSONL window the gate uses (7 days default, 24 h toggle). The card
  subtitle always states the window: "last 24 h · 312 signals".
- **Staleness line** (shared copy): `BackgroundAlerts.lastCheckedLabel`
  — "last checked Xm ago", never silent. A check older than 2× the
  scheduler cadence renders the cards dimmed with a "stale" badge.

### Empty / new-device state

No rows yet ⇒ "No signals recorded in this window — quiet is healthy."
(An empty window is healthy-with-null-rates per the SLO spec; the UI
says so in plain words.)

## 3. Data path (on-device only)

```text
delivery.log (+ .1, .2) → parseLogLines → evaluateSlo → cards
tick stats (in-memory tracker + MetricsHistory p95 convention)
```

- The view layer calls the SAME pure functions (`parseLogLines`,
  `buildCheckReport`) the `agent_check` CLI uses — one evaluation
  path, two surfaces. A widget test pins card thresholds against
  `AlertSlo` constants so a threshold change breaks the test first.
- Titles only on screen; tapping a title opens the existing alert
  detail — the dashboard adds no navigation stack.

## 4. Accessibility + honesty

- Cards expose semantics labels ("Delivery 99 point 2 percent, target
  99 percent") — screen-reader first, color never the only signal
  (each state also has text: On track / Watch / Breach).
- A breach card links the runbook section for that SLO
  (`docs/runbooks/`), not a generic help page.
- The dashboard NEVER shows a notification-style banner itself — it
  is a quiet surface; alerting stays in the OS rail.

## 5. QA hooks (Balqis, TM-6)

- Deterministic fixture: a checked-in `delivery.log` sample driving
  all four cards through green/amber/red in a widget test.
- Zero-egress check: dashboard session under test emits no HTTP
  (existing `qa_mock_real_gap` harness pattern).
- Gate evidence: `agent_check --check --json` output for the soak
  window is attached to the Beta.2 exit review; the dashboard is the
  human-readable mirror of that JSON.
