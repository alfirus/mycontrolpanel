# GO/HOLD Checklist Input — Release Gate (QA → Burhanah)

Owner: Balqis (QA Engineer) · For: Burhanah (Release Verifier, gate verdict
GO/HOLD) · Date: 2026-10-28 · Commit verified: `main`.
This card is QA's evidence input — Burhanah owns the verdict.
Companion docs: `docs/qa/release-test-plan-server-status.md`,
`docs/qa/regression-checklist-alerts-cron-apps.md`,
`docs/qa/mock-vs-real-gap-report.md`.

## QA recommendation: CONDITIONAL GO (ship with Security HOLD)

| Gate area | QA signal | Evidence |
|-----------|-----------|----------|
| Install (SSH/agent) | GO if matrix green | Plan M1–M9 + IN-01–09; agent v2 `/metrics` + `/procstats` schema pinned by `test/agent_protocol_test.dart` |
| Latency/uptime accuracy | GO | Latency = measured agent round-trip (`MetricsHistory.record` per poll); uptime days from agent `/proc/uptime`; p95 math pinned by `test/qa_mock_real_gap_test.dart` |
| Settings CRUD persistence | GO with note | Servers/tokens via `SecureStore` (Keychain/Keystore) with SharedPreferences migration (`settings_screen.dart:71,111`); full migration tracked in #25 — verify no plaintext remainder before stable |
| Alerts/Cronjobs/Apps | GO | Live SSH discovery + thresholds pinned by `test/qa_regression_test.dart`; foreground watcher verified, background push out of scope by design |
| Log Tail | GO | Real SSH path verified; minor mock-bleed filed as #63 (P2) |
| Metrics KPIs | GO with note | p95 honestly live; static Uptime/Errors/Req-min filed as #62 (P2) — do not cite those KPIs as release evidence |
| Security Watch | HOLD | Fully mock, no live source — filed as #61 (P1). Exclude from GO claims until wired or demo-gated |

## Blocking map (what fails the gate)

- HOLD trigger: any P0 defect in install/metrics/CRUD, or Security Watch
  presented as live evidence (see #61).
- Non-blocking: #62, #63 (P2) — ship with known-issue notes.
- Pre-existing context: #19 (GitHub tab mock), #21 (CI/CD demo), #23
  (alerts background delivery), #25 (secure-storage migration tail).

## QA sign-off procedure

1. Confirm all four required checks green on the release candidate
   (analyze / gitleaks / osv-scan / test).
2. Run the release plan matrix rows M1–M9 on the candidate build.
3. Re-run `flutter test` (includes `qa_regression_test.dart`,
   `qa_mock_real_gap_test.dart`, `agent_protocol_test.dart`).
4. If 1–3 pass with no P0/P1 open outside #61's Security scope:
   QA input = CONDITIONAL GO as tabled above; verdict to Burhanah.
