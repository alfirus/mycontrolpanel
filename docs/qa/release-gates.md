# Release gates — MOCK-to-real acceptance (Burhanah, Release Verifier)

Owner: Burhanah (Release Verifier — gate verdicts are binding) · Date: 2026-10-28
Commit verified: `main` @ `b029509` (merge #82) + this PR's CI run.
Companion inputs (consumed, not re-decided): `docs/qa/go-hold-checklist.md`,
`docs/qa/mock-vs-real-gap-report.md`,
`docs/qa/regression-checklist-alerts-cron-apps.md`,
`docs/qa/release-test-plan-server-status.md` (all Balqis, merged).
Executable proof: `test/release_gate_proof_test.dart` — CI runs it; the gate
reads CI's output, never pasted logs.

## 0. Milestone anchor + mapping gap

Live on `main` (re-verified via `gh api` 2026-10-28): milestones **M3
(v1.0.0-alpha.2, 4 open issues), M4 (beta.1), M5 (v1.0.0)** plus
acceptance-criteria issues **#16/#18/#20/#22/#24/#26** (all open) and
mock-gap issues **#19/#21/#23/#25**.

MAPPING GAP (noted, not blocking): Rina's roadmap docs are still **open PRs,
not on `main`** — #15 (ROADMAP), #27 (BACKLOG), #29 (RISKS), #31 (STATUS).
These gates therefore anchor to the **live milestones + issues** above. When
#15/#27/#29/#31 merge, re-map §1–§3 lane rows to their exit criteria; until
then any verdict citing a roadmap exit clause stays HOLD.

## 1. MOCK-to-real acceptance gates (GO/HOLD + required receipts)

A lane goes GO only when its receipt is re-verified by the verifier (CI run,
read-back, or live probe). A worker's summary is a claim; the receipt is the
fact. Anything failing stays HOLD with the reason named.

| Lane | GO criteria | Required receipt | Current verdict |
|---|---|---|---|
| GitHub | Issues/PRs live over PAT via `GithubService`; token in keychain; no mock tab without an explicit demo banner | CI green + `test/github_repo_test.dart` pass on the wiring PR; read-back: token read via `SecureStore.readSecret('github_token')`, never prefs | HOLD — #16 open, #19 (mock tab) open; PR #80 merged the `GithubRepo` contract only |
| CI/CD | Timeline shows live Actions runs; failure surfacing; poll cadence + caching; offline fallback to last snapshot | CI green on the wiring PR; read-back of a live run list against the API in the PR's CI log or a verifier probe | HOLD — #18 open, #21 (demo deploys) open; PR #83 open, unreviewed by verifier |
| Logs | Real SSH tail (`LogTailService.fetch`, journal/syslog/docker, 100 lines); parser total; no mock bleed under a LIVE title | `test/qa_mock_real_gap_test.dart` + `test/log_stream_test.dart` green in CI | CONDITIONAL GO — real path verified; #63 (mock bleed on fetch failure) is P2, ship only with the known-issue note |
| Security | Live findings source OR the segment is demo-gated; never presented as live evidence | Live source wired + test pin, or an explicit demo label in UI | HOLD — #61 filed P1 (fully mock, no live source); excluded from all GO claims until wired or gated |
| AI | Chat replies labelled live vs local/demo; provider fallback chain logged (`llm-fallback-log`); no secret in prompts/logs | `test/llm_reliability_test.dart` + `test/chat_context_test.dart` green; `redactForLog` pin green | GO on labelling + fallback logging; HOLD on any new model wiring until Alya's scope/token review lands |
| Metrics | Latency = measured agent round-trip; uptime from agent `/proc/uptime`; p95 honestly computed | `test/qa_mock_real_gap_test.dart` (G2) green; static Uptime/Errors/Req-min must NOT be cited (#62 P2) | CONDITIONAL GO — p95 live; #62 static-KPI note mandatory |

Global static gates (unchanged, owned by `ci.yml` + `security.yml`): `test`
(flutter test), `analyze`, `osv-scan`, `gitleaks` — all green, MERGEABLE,
before any merge. Branch protection on `main` must require them.

## 2. Alert proof re-run (from actual test output, never pasted logs)

Trigger table — each row re-verified by `test/release_gate_proof_test.dart`
(R1–R6) running in **this PR's CI `test` job**; quote the CI run id + result
as the receipt at release time:

| # | Trigger | Boundary pinned in test |
|---|---|---|
| R1 | Disk warn ≥80%, critical ≥90% (per mount) | 0.79 quiet · 0.80 warning · 0.90 critical · mount in title |
| R2 | Failed systemd units | every unit critical (`Service failed: <name>`), blanks skipped, empty list quiet |
| R3 | Brute force (failed SSH logins / 24h) | 4 quiet · 5 warning · 20 critical + `(possible brute force)` label |
| R4 | Load vs CPU count | at cap (4.0/4) quiet · above warn · past 2× critical · unknown nproc skips |
| R5 | Kernel lines | OOM line critical (`Out-of-memory`) · other err/warn lines warning |
| R6 | Reboot tripwire (uptime <1h) | null quiet · 3599s warns (`unexpected restart`) · 3600s quiet |
| R7 | Credential audit (proof-test group) | `findRawCredentials` flags plaintext, `secure:` refs + blanks clean |
| R8 | Agent install contract (proof-test group) | `AgentService.agentPort == 9108`, script + unit carry 9108 / `mcp-agent` markers |

Full-matrix rows ( Balqis AL-01–AL-12 + cron/app discovery) remain pinned by
`test/qa_regression_test.dart` + `test/alert_rules_test.dart`; this file does
not duplicate them, it binds their thresholds to the gate so a silent
relaxation fails CI. SSH-live rows still need the lab host harness (manual
until it exists — see the QA regression checklist).

## 3. Credential + agent-install gates (HOLD with reasons)

**C1 Credential migration — HOLD** (tracks #17 mandated Option-A, #22 audit,
#25 migration tail). GO requires ALL of:
1. `SecureStore.migrateIfNeeded()` one-time, idempotent (flag
   `secrets_migrated_v1`) — implemented.
2. Read-back confirmation on a fresh + an upgrade install: tokens read via
   `SecureStore.readSecret('github_token'|'gitlab_token'|'ai_key')`;
   `SecretHygiene.findRawCredentials(decodedServers)` returns empty;
   `prefs.getString('github_token'|'gitlab_token'|'ai_key')` returns null.
   Until those three read-backs are posted as evidence, the gate stays HOLD —
   code presence is not migration proof.
3. `redactForLog` on every log/crash path carrying server maps
   (`test/secret_hygiene_test.dart` green — currently passing).

**C2 Agent install (:9108 systemd) — HOLD** (tracks #20 background/polling
scope + release-test-plan matrix M1–M9). GO requires a real-server install
log showing all five read-backs in order: `SUDO_OK` → `UPLOADED` →
`systemctl is-active mcp-agent` = `active` → port line for `9108` (or
explicit `PORT_CHECK_SKIP` with reason) → `Verified: cpu=… ram=… disk=…
uptime=…d` from `GET http://host:9108/metrics`. The one-click path
(`AgentService.install`) and the manual path (`manualInstallCommand` ending
in `AGENT_OK`) both count; post the full log, not excerpts.

## 4. Verdicts on open lane PRs (verifier reviews)

- #83 deployments-service (CI/CD lane): **HOLD pending verifier review** —
  may not be cited as the CI/CD receipt (§1) until reviewed + CI green read
  by the verifier.
- #81 cicd run-detail, #85 alert-notifications, #84 SSH TOFU, #77
  state-views, #86 APM-lite: **no gate verdict yet** — each needs its own
  receipt check at review time against §1 rows.
- #80 (GithubRepo contract), #79 (alert-rules), #82 (agent log stream):
  merged building blocks, **not** lane GO evidence on their own.

## 5. What fails the gate (blocking map)

HOLD triggers: any P0 defect in install/metrics/CRUD; Security Watch cited
as live evidence (#61); a lane claimed GO without its §1 receipt; alert
thresholds changed without updating §2 + the proof test; credentials claimed
migrated without the §3-C1 read-backs; agent install claimed without the
§3-C2 five-line log. Non-blocking: #62, #63 (P2 — ship with notes).

Sign-off: gate checked by Burhanah (this doc + proof test CI) · CEO (Sofia)
release approval still required for the tag.
