# Predictive disk/load alerting (Farah — ML)

## What
`lib/services/forecast_alerts.dart` (stdlib only: `dart:math`) adds
early-warning forecasts on top of the capped on-device `MetricsHistory`
series:

- `DiskForecaster` — least-squares trend on disk usage → ETA (hours) to
  the 80% (warning) and 90% (critical) lines. Null when flat/shrinking,
  untrusted (R² < 0.5), or under-minimum history. Design note: the
  `LoadSpikeForecaster` gate deliberately uses the history **median**,
  not p95 — a sustained spike poisons a p95 gate within a few samples
  (verified during development).
- `LoadSpikeForecaster` — EWMA vs `max(floor, median × 1.8)`: per-host
  adaptive, no fixed load number, past-only history so the judged spike
  cannot move its own gate.
- `percentile` — nearest-rank p50/p95/p99 helper (same method as
  `MetricsHistory.p95`), for display-ranked "how unusual" context.

## Wiring notes for Nadia (serving/ops)
- No serving changes; all on-device.
- Suggested wiring: after each agent poll, build `TrendPoint`s from
  `MetricsHistory.read(host)` (timestamps → hours) and run both
  forecasters. Emit `info`-severity "upcoming" alerts (`disk 90% in ~Xh`,
  `load spiking on H`) distinct from firing alerts.
- Eval: `flutter test test/forecast_alerts_test.dart` (deterministic).
  Re-tune `minRSquared`/`ratio`/`absoluteFloor` per fleet if noisy.
