# Log failure classifier (Farah — ML)

## What
`lib/services/log_classifier.dart` (zero imports, no new pubspec entries)
classifies each `LogTailService` line into `authBruteForce / diskError /
kernelIssue / appError / benign` with a 0..1 confidence:

- Ordered rule groups: high-specificity security/kernel/disk patterns win
  over the generic error fallback; an explicit benign class (startup,
  reload, ok, systemd targets, session open/close) keeps routine tails
  quiet, with unmatched lines defaulting to low-confidence benign.
- `classifyBatch` aggregates a tail into per-category counts + top
  alertable findings for the Alerts engine / a Security Watch badge.

## Wiring notes for Nadia (serving/ops)
- No serving changes; all on-device.
- Suggested wiring: run `classifyBatch` over each fetched log tail
  (journal/syslog/docker) and map `authBruteForce` → Security Watch,
  `diskError`/`kernelIssue` → warning/critical alerts with `signal` +
  `confidence` in the subtitle. Counts feed dashboard badges.
- Eval: `flutter test test/log_classifier_test.dart` (deterministic).
  Extend `_rules` with fleet-specific patterns; keep the benign
  negative-class assertions passing so routine lines never page.
