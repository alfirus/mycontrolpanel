# MOCK-vs-Real Gap Report — Log Tail, Metrics p95, Security Watch

Owner: Balqis (QA Engineer) · Date: 2026-10-28 · Commit verified: `main`
(`7f9fe4d` + quality-gates). Method: static verification of the live path in
`lib/screens/control_center_screen.dart` + `lib/services/log_tail_service.dart`
+ `lib/services/metrics_history.dart` against each segment's acceptance
criterion. Executable pins: `test/qa_mock_real_gap_test.dart`.

Mode switch (ground truth): `_useRealServers => _savedServers.isNotEmpty`
(`control_center_screen.dart:70`). No servers → demo; servers saved → live.

## G1. Log Tail — PASS (real path verified, one minor gap filed)

Acceptance: streaming terminal with level filters backed by real SSH logs.
Verdict: PASS.

- Real path exists: `_pollRealLogs` calls `LogTailService().fetch` with
  source picker journal/syslog/docker, 100 lines over SSH (`:363`), Docker
  container auto-picked from discovered apps, errors surfaced (`_logError`).
- Demo mode is honest: title `LIVE LOG TAIL` + subtitle
  `demo stream — add servers for real SSH logs` (`:2886`); synthetic
  heartbeat (3s timer, `:1106`) is skipped entirely in real mode (`:1108`).
- Parser is total: `LogTailService.parse` never throws, unparseable lines
  become INFO, container names sanitized, 300-char truncation.
- MINOR GAP (filed as issue): `_liveLogs` is initialized from `mockLogs`
  (`:60`) and `_pollRealLogs` only replaces it when `lines.isNotEmpty`
  (`:369`). On fetch failure/empty result in real mode, demo lines persist
  under the `LIVE LOG TAIL • <server>` title — mock bleed behind a live label.

## G2. Metrics p95 — CONDITIONAL PASS (real p95 verified, demo-KPI gap filed)

Acceptance: latency p95 chart + Uptime/p95/Errors/Req-min KPIs.
Verdict: CONDITIONAL PASS.

- Real path exists: every agent poll records per-host latency
  (`MetricsHistory.record`, `:289`); live segment merges histories and
  computes `MetricsHistory.p95` + `formatMs` (`:2953-2957`); empty history
  renders `—`, flat-line chart. p95 math + formatting pinned by unit tests.
- GAP (filed as issue): in demo mode the KPIs show static values
  (`Uptime 99.92%`, `p95 48ms`, `Errors 0.31%`, `Req/min 6.2k`) with no demo
  qualifier (title is bare `METRICS`, no subtitle), and Uptime/Errors/Req-min
  stay static even in `METRICS • LIVE` mode — only p95 goes live. Static
  numbers presented as measurements mislead release judgment.

## G3. Security Watch — FAIL (fully mock, gap filed)

Acceptance (roadmap): findings with severity + category backed by live signal.
Verdict: FAIL — no live source exists.

- `_securitySegment` renders `mockSecurity` unconditionally (`:3004`); no
  `_useRealServers` branch, no `LIVE` title variant, unlike every other
  segment. Findings (TLS expiry, brute-force IP, CVE, S3 bucket, 2FA) are
  compile-time constants in `lib/models/mock_data.dart:151-156`.
- Partial live signals already exist elsewhere and could feed it: SSH
  brute-force counts (`fetchAlerts` auth probe), open-port discovery
  (`fetchApps` ss/netstat + `/procstats` ports). No wiring yet.
- GAP (filed as issue): wire a live Security source or label the segment
  demo-gated; until then Security Watch must read HOLD on the release gate.

## Summary table

| Segment | Live path | Demo labeling | Verdict |
|---------|-----------|---------------|---------|
| Log Tail | SSH journal/syslog/docker + parser | Labeled (`demo stream…`) | PASS (minor bleed filed) |
| Metrics p95 | Ring buffer + real p95 KPI | p95 live; other KPIs static unlabeled | CONDITIONAL PASS (filed) |
| Security Watch | None — `mockSecurity` always | None — no LIVE variant | FAIL (filed) |

Defects filed as repo issues with repro steps (see issue links), not chat messages.
