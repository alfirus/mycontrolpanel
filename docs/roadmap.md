# Roadmap — live-vs-mock matrix + phased plan

Source-of-truth companion to the README's "What works today vs what's
mock" section. Status as of `v1.0.0-alpha.1+1` (main). This single file
combines the per-screen matrix (Ain) with the phased execution plan
(Rina, PM — folded in from the `docs/ROADMAP.md` proposal; one file,
lowercase name).

Legend: **Live** = reads real infrastructure. **Partial** = live when
configured, demo content otherwise. **Mock** = demo data only; API wiring
is on the roadmap.

| Screen / segment | Status | Data source today | Gap to close |
|---|---|---|---|
| Server Status (CPU/RAM/disk, latency, uptime) | Partial | Metrics agent `:9108` (`GET /metrics`); demo servers when none configured | None for connected hosts — no demo fallback while connected (release-gate bar) |
| Metrics & Uptime (p95 chart, KPIs) | Partial | Per-host latency/CPU ring buffer (`MetricsHistory`, cap 120) + agent; mock blend with no history yet | Retention policy, per-server caps, export (Phase 2) |
| Cronjobs | Partial | Live SSH discovery (`crontab`, `/etc/crontab`, `/etc/cron.d/*`); demo when no servers | Last-run tracking is in; nothing open for connected hosts |
| Apps | Partial | Live SSH discovery (systemd, Docker, listening ports) + agent v2 `/procstats` (top processes, per-port connections); demo when no servers | `gitlab_service.dart` stub: promote or delete (post-1.0) |
| Alerts | Partial | Live SSH harvest (failed units, disk ≥80/90%, brute force, load, kernel errors, reboots) + foreground watcher (diffed against last-seen set); demo when no servers | Background polling + push while closed (Phase 2) |
| Terminal | Live | Built-in SSH (`dartssh2`) + local shell per saved server | None |
| Live Log Tail | Partial | Real journal/syslog/docker tail over SSH per saved server (refresh on poll tick); seeded demo heartbeat only when no servers exist | None for connected hosts |
| GitHub (Issues / PRs / Tasks) | Mock | `mockIssues` / `mockPRs` / `mockTasks` (tab hard-titled `GITHUB • DEMO`) | Wire live REST + Projects v2 GraphQL via `GithubService`, token from secure store, pagination, rate limits (Phase 1, item 1) |
| GitLab | Mock | Same mock sets (tab hard-titled `GITLAB • DEMO`; `gitlab_service.dart` is a stub) | Live data over PAT, or explicit demo-mode banner (release-gate bar) |
| CI/CD & Deployments | Mock | `mockDeploys` (timeline hard-titled `CI/CD • DEMO`) | Live workflow runs, or explicit demo-mode banner (Phase 1, item 2) |
| Security Watch | Mock | `mockSecurity` findings list | Live source or cut (Phase 1, item 1) |
| AI Chatbox | Partial | Real multi-provider streaming (OpenAI / Anthropic / Gemini / Ollama / OpenRouter / LM Studio / OpenCode Zen-Go, SSE/NDJSON + tool calling, audit trail capped at 200) when a provider is configured; mock replies otherwise | Label replies honestly live vs local/demo (release-gate bar) |
| Settings | Live | Server connections + prefs; secrets in `flutter_secure_storage` (Keychain/Keystore) with one-time `SharedPreferences` migration | Audit every credential path into `SecureStore` — no raw secret left in prefs JSON (Phase 1, item 4) |

## Phased plan

Phase names map 1:1 to GitHub milestones. Every Mock row above maps to a
Phase 1 "kill the mocks" item (see the Gap column for the item number).

### Phase 0 — Foundation (DONE, shipped on main)

- Real SSH data path: metrics via stdlib Python agent `:9108`, cron/app/alert
  discovery over SSH, one-click agent install, built-in terminal.
- Secure credentials: `flutter_secure_storage` (Keychain/Keystore) with
  SharedPreferences migration (`SecureStore.migrateIfNeeded`, one-time flag
  `secrets_migrated_v1`).
- APM-lite: agent v2 `/procstats` (top processes, per-port connections).
- GitHub Projects v2 (GraphQL) Tasks tab, in-app updates from GitHub Releases,
  streaming AI chat + tool calling, AI audit trail (capped at 200).
- CI: `security.yml` gate (analyze + OSV scan + gitleaks) on PRs to main;
  `release.yml` builds macOS/Windows/Linux on `v*` tags.

### Phase 1 — Kill the mocks (milestone: `v1.0.0-alpha.2`)

Goal: every "Mock (API-ready)" row in the README features table becomes live
or is cut. Exit criteria per item in BACKLOG.md:

1. **Real GitHub API wiring** — Issues/PRs tab reads live REST
   (`GithubService` exists; wire token from secure store, paginate, handle
   rate limits). Security findings tab: live source or cut.
2. **Actions CI/CD live** — deployment timeline reads real workflow runs.
3. **Alert polling** — foreground watcher merged and verified against
   a real firing signal (failed unit + disk ≥80%); background polling scoped
   in Phase 2.
4. **Secure storage completion** — audit every credential path (PATs, AI keys,
   SSH key content) into `SecureStore`; no raw secret left in prefs JSON
   (only `secure:` markers).

Milestone exit: `flutter analyze` + `flutter test` green, README mock-table
updated to reflect reality, alpha.2 tag cut via `release.yml`.

### Phase 2 — Background + lock (milestone: `v1.0.0-beta.1`)

1. **Background alert polling + push notifications** — alert on new firing
   signals / failed CI runs while the app is closed (per-platform constraints:
   macOS/Windows/Linux/iOS/Android differ — design doc first).
2. **Biometric app lock enforcement** — `local_auth` + lock screen; the
   Settings toggle persists today but enforces nothing.
3. **Metrics history retention** — build on the metrics history: retention
   policy, per-server caps, export.

Milestone exit: beta.1 tag, notifications verified on at least desktop + one
mobile OS, lock enforced on cold start and resume.

### Phase 3 — Release hardening (milestone: `v1.0.0`)

1. **Sentry / Datadog integration** — placeholder row in Settings becomes a
   real opt-in crash/error reporter (privacy note: self-hosted users).
2. **Release checklist institutionalised** — STATUS.md checklist run for every
   `v*` tag; tag notes generated from closed milestone issues.
3. **Docs pass** — screenshots current, macOS sandbox notes verified against
   latest Xcode, Linux deps list verified in clean container.

Milestone exit: v1.0.0 tag, all three milestones closed, store/distribution
artifacts attached to the GitHub Release.

### Post-1.0 (backlog, no milestone yet)

- Multi-window / tray mode for desktop; Android background-service limits.
- GitLab parity (a `gitlab_service.dart` stub exists — promote or delete).
- Offline-first cache of last-known server state.

## Link map

- Backlog with acceptance criteria: `docs/BACKLOG.md` (GitHub issues mirror it).
- Dependency + risk register: `docs/RISKS.md`.
- Release + status cadence: `docs/STATUS.md`.
- Release bar for any `v*` tag: no MOCK-tab ships as live — unwired tabs
  carry an explicit demo-mode banner. Full gate: `docs/release-gate.md`.

## Updating this file

When a Mock row goes live: flip its Status, move the detail into the
Data-source column, and check off the matching Phase 1 item in the same PR.
The README section mirrors this file in compact form — keep the two in sync.
Weekly: STATUS.md gets a dated entry (done / in-flight / blocked +
burndown against the open milestone). Cadence owned by Rina.
Every PR that flips a mock to live MUST update the README features table
and close its backlog issue; otherwise the security gate passes but the PM
gate (review) does not.
