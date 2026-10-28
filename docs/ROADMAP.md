# MyControlPanel Roadmap

Version: 1.0.0-alpha.1+1 (current) · Owner: Rina (PM) · Updated: 2026-10-28

Source of truth for "what works today vs what's mock" is the README's
**What works today vs what's mock** section. This roadmap turns every honest
mock and every unchecked README roadmap item into a phased plan with exit
criteria. Phase names map 1:1 to GitHub milestones.

## Phase 0 — Foundation (DONE, shipped on main)

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
- Open contribution in flight: PR #13 (real SSH log tail, metrics history with
  live p95, foreground alert watcher) — lands in Phase 1 on merge.

## Phase 1 — Kill the mocks (milestone: `v1.0.0-alpha.2`)

Goal: every "Mock (API-ready)" row in the README features table becomes live
or is cut. Exit criteria per item in BACKLOG.md:

1. **Real GitHub API wiring** — Issues/PRs tab reads live REST
   (`GithubService` exists; wire token from secure store, paginate, handle
   rate limits). Security findings tab: live source or cut.
2. **Actions CI/CD live** — deployment timeline reads real workflow runs
   (builds on the live-runs work already merged in #2/#6).
3. **Alert polling** — foreground watcher (PR #13) merged and verified against
   a real firing signal (failed unit + disk ≥80%); background polling scoped
   in Phase 2.
4. **Secure storage completion** — audit every credential path (PATs, AI keys,
   SSH key content) into `SecureStore`; no raw secret left in prefs JSON
   (only `secure:` markers). Linux `libsecret-1-dev` dependency documented
   (fixed in #11 — keep in release notes).

Milestone exit: `flutter analyze` + `flutter test` green, README mock-table
updated to reflect reality, alpha.2 tag cut via `release.yml`.

## Phase 2 — Background + lock (milestone: `v1.0.0-beta.1`)

1. **Background alert polling + push notifications** — alert on new firing
   signals / failed CI runs while the app is closed (per-platform constraints:
   macOS/Windows/Linux/iOS/Android differ — design doc first).
2. **Biometric app lock enforcement** — `local_auth` + lock screen; the
   Settings toggle persists today but enforces nothing.
3. **Metrics history retention** — build on PR #13's history: retention
   policy, per-server caps, export.

Milestone exit: beta.1 tag, notifications verified on at least desktop + one
mobile OS, lock enforced on cold start and resume.

## Phase 3 — Release hardening (milestone: `v1.0.0`)

1. **Sentry / Datadog integration** — placeholder row in Settings becomes a
   real opt-in crash/error reporter (privacy note: self-hosted users).
2. **Release checklist institutionalised** — STATUS.md checklist run for every
   `v*` tag; tag notes generated from closed milestone issues.
3. **Docs pass** — screenshots current, macOS sandbox notes verified against
   latest Xcode, Linux deps list verified in clean container.

Milestone exit: v1.0.0 tag, all three milestones closed, store/distribution
artifacts attached to the GitHub Release.

## Post-1.0 (backlog, no milestone yet)

- Multi-window / tray mode for desktop; Android background-service limits.
- GitLab parity (a `gitlab_service.dart` stub exists — promote or delete).
- Offline-first cache of last-known server state.

## How this stays current

- Weekly: STATUS.md gets a dated entry (done / in-flight / blocked +
  burndown against the open milestone). Cadence owned by Rina.
- Every PR that flips a mock to live MUST update the README features table
  and close its backlog issue; otherwise the security gate passes but the PM
  gate (review) does not.
- No Ain (docs) or Shiela (milestones/labels) PRs were merged as of 2026-10-28;
  file placement under `docs/` follows the existing repo convention
  (`docs/screenshots/`). Overlap risk is low; flagged in PR bodies regardless.

## Link map

- Backlog with acceptance criteria: `docs/BACKLOG.md` (GitHub issues mirror it).
- Dependency + risk register: `docs/RISKS.md`.
- Release + status cadence: `docs/STATUS.md`.
