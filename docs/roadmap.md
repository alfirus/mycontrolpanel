# Live vs Mock — per-screen data-source matrix

Source-of-truth companion to the README's "What works today vs what's
mock" section. Status as of `v1.0.0-alpha.1+1` (main, incl. PR #13).

Legend: **Live** = reads real infrastructure. **Partial** = live when
configured, demo content otherwise. **Mock** = demo data only; API wiring
is on the roadmap.

| Screen / segment | Status | Data source today | Gap to close |
|---|---|---|---|
| Server Status (CPU/RAM/disk, latency, uptime) | Partial | Metrics agent `:9108` (`GET /metrics`); demo servers when none configured | None for connected hosts — no demo fallback while connected (release-gate bar) |
| Metrics & Uptime (p95 chart, KPIs) | Partial | Per-host latency/CPU ring buffer (`MetricsHistory`, cap 120) + agent; mock blend with no history yet | Retention policy, per-server caps, export (Rina Phase 2) |
| Cronjobs | Partial | Live SSH discovery (`crontab`, `/etc/crontab`, `/etc/cron.d/*`); demo when no servers | Last-run tracking is in; nothing open for connected hosts |
| Apps | Partial | Live SSH discovery (systemd, Docker, listening ports) + agent v2 `/procstats` (top processes, per-port connections); demo when no servers | `gitlab_service.dart` stub: promote or delete (post-1.0) |
| Alerts | Partial | Live SSH harvest (failed units, disk ≥80/90%, brute force, load, kernel errors, reboots) + foreground watcher (diffed against last-seen set); demo when no servers | Background polling + push while closed (Rina Phase 2) |
| Terminal | Live | Built-in SSH (`dartssh2`) + local shell per saved server | None |
| Live Log Tail | Partial | Real journal/syslog/docker tail over SSH per saved server (refresh on poll tick); seeded demo heartbeat only when no servers exist | None for connected hosts |
| GitHub (Issues / PRs / Tasks) | Mock | `mockIssues` / `mockPRs` / `mockTasks` (tab hard-titled `GITHUB • DEMO`) | Wire live REST + Projects v2 GraphQL via `GithubService`, token from secure store, pagination, rate limits (Rina Phase 1, item 1) |
| GitLab | Mock | Same mock sets (tab hard-titled `GITLAB • DEMO`; `gitlab_service.dart` is a stub) | Live data over PAT, or explicit demo-mode banner (release-gate bar) |
| CI/CD & Deployments | Mock | `mockDeploys` (timeline hard-titled `CI/CD • DEMO`) | Live workflow runs, or explicit demo-mode banner (Rina Phase 1, item 2) |
| Security Watch | Mock | `mockSecurity` findings list | Live source or cut (Rina Phase 1, item 1) |
| AI Chatbox | Partial | Real multi-provider streaming (OpenAI / Anthropic / Gemini / Ollama / OpenRouter / LM Studio / OpenCode Zen-Go, SSE/NDJSON + tool calling, audit trail capped at 200) when a provider is configured; mock replies otherwise | Label replies honestly live vs local/demo (release-gate bar) |
| Settings | Live | Server connections + prefs; secrets in `flutter_secure_storage` (Keychain/Keystore) with one-time `SharedPreferences` migration | Audit every credential path into `SecureStore` — no raw secret left in prefs JSON (Rina Phase 1, item 4) |

## How to read this with Rina's plan

- Execution order, milestones, and exit criteria live in Rina's phased
  roadmap: PR #15 (`docs/ROADMAP.md`, milestone-mapped Phase 0–3). **That
  plan is authoritative on sequencing; this file is authoritative on
  per-screen live-vs-mock status.** If the two disagree on a screen's
  status, this file wins and the roadmap PR should be updated.
- Every Mock row above maps to a Phase 1 "kill the mocks" item in PR #15
  (see the Gap column for the item number).
- Release bar for any `v*` tag: no MOCK-tab ships as live — unwired tabs
  carry an explicit demo-mode banner. Full gate:
  `docs/release-gate.md` (PR #30, in review).
- Filename note: this file is `docs/roadmap.md` (this task's spec) while
  Rina's proposal is `docs/ROADMAP.md` — identical ignoring case, which
  collides on case-insensitive filesystems. When PR #15 merges, reconcile
  to a single file (suggest keeping `ROADMAP.md` as the phased plan and
  folding this matrix into it, or vice versa) rather than carrying both.

## Updating this matrix

When a Mock row goes live: flip its Status, move the detail into the
Data-source column, and check off the matching item in Rina's roadmap in
the same PR. The README section mirrors this file in compact form — keep
the two in sync.
