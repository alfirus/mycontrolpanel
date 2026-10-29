# Anomaly baselines (Farah — ML)

## What
`lib/services/anomaly_baseline.dart` (stdlib only: `dart:math`) replaces
static CPU/RAM/disk/load/latency thresholds with unsupervised baselines:

- `RollingStats` — Welford online mean/variance.
- `ZScoreDetector` — sliding-window z-score, flags |z| >= 3.
- `MadDetector` (default) — median/MAD modified z-score, robust to a
  single spike poisoning the baseline.
- `AnomalyBaseline` — per-metric wrapper (`host/metric`) with warmup
  gating (`warmup` verdict until `minHistory` samples).

## Wiring notes for Nadia (serving/ops)
- No serving changes; all on-device.
- Suggested wiring: one `AnomalyBaseline` per host×metric, fed from each
  `:9108 /metrics` poll (and latency from `MetricsHistory`). Route
  `AnomalyResult.isAnomaly` into the Alerts engine next to the static
  rules; use `score` for ranking and `baseline`/`deviation` for the
  alert subtitle.
- Eval: `flutter test test/anomaly_baseline_test.dart` (deterministic,
  no randomness). Tune `window`/`threshold` per metric if noisy hosts
  over-fire.
