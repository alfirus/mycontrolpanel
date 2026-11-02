# Changelog — MyControlPanel

All notable changes to this project are recorded here, newest first.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
releases are cut as Git tags `v<name>` via `.github/workflows/release.yml`
(see [Release checklist](docs/releases.md)).

## [Unreleased]

### Added
- Alert reliability harness + SLOs (Nadia, Beta.2 instrumentation):
  `lib/services/alert_reliability.dart` (pure-Dart lifecycle tracking
  scheduled/executed/notified/dismissed, latency, drops, agent CPU/mem
  samples, frozen SLOs: 99% within 5 min, <1% drops, p95 <2 s tick,
  p95 <50 MB agent) with `test/alert_reliability_test.dart` and
  `docs/specs/alert-reliability-slos.md`. No behavior change to the
  shipping tick; no new dependencies.
- Headless-agent operability (Nadia, Beta.2): `bin/agent_check.dart`
  (`--check --json` SLO report with headless-mirrored exit codes,
  `--rotate` log rotation), pure-Dart builders
  (`agent_operability.dart`, `alert_log_rotation.dart`: 512 KiB × 3
  generations) with tests, hardened scheduler templates with
  restart/backoff (`scripts/reliability/`), local-only opt-in SLO
  dashboard spec. No new dependencies.
- Beta exit + GTM readiness (Sofia, docs/decision only — no behavior
  change): `docs/beta-done-checklist.md` (beta.1 DONE list, Burhanah
  sign-off block), decision `004-tray-build-vs-defer.md` (owner call:
  build Beta.2 per Rina's plan vs defer), `docs/store/` (listing copy,
  screenshot checklist, privacy/permission disclosures for Play, App
  Store, Snap, Microsoft Store), `docs/sales-kit-review.md` (Syafiqah +
  Naura conditional-GO review with pre-call fixes).
- Tray-mode delivery program (Beta.2 plan, docs only — no behavior
  change): `docs/project/tray-mode-plan.md` (WBS TM-1…TM-8, critical
  path, RACI, top-5 risks), roadmap Phase 2b exit gate (`v1.0.0-beta.2`),
  closed-app architecture (§8 of `docs/design/05-background-alerting.md`).
- Beta.2 tracking (Shiela, TM-8): milestone `v1.0.0-beta.2`, epic #119 +
  children #121–#125, backlog index, PR Markdown link-check workflow,
  weekly stale-triage pings. Wording reconciled with Rina's tray-mode plan
  (`--poll-headless` contract, WBS owners, Beta.2 gate). No app code.
- Beta verifiable release gate (Burhanah): stdlib-only
  `tool/verify_release.py` (version==CHANGELOG==tag, 3 fresh platform
  assets + SHA256SUMS, flutter test + agent pytest re-run, consent/Sentry
  default-off pins, MIT headers) emitting `release-proof.json`; required
  `verify-gate` job in `release.yml` blocks publish on HOLD; gate + waiver
  rules in `docs/release-gates.md` (owner waiver via Sofia only).
- Agent install-contract pytest suite (`agent/tests/`): port :9108, unit
  markers, installer defaults, app/payload endpoints.
- SPDX-MIT headers on all `lib/**/*.dart` (pinned by gate C6).
- README real-vs-roadmap status matrix (live vs UI-ready per capability).
- Launch landing copy draft (`docs/launch.md`): hero, features, pricing tiers.
- Sales one-pager (`docs/sales-one-pager.md`): use cases + objection handling.
- Launch hero pack, feature infographics, and social teaser cards
  (`assets/marketing/`, `docs/infographics/`, `docs/social-teasers.md`).
- Real SSH log tail (journal/syslog/docker) with per-server source picker.
- Metrics history (per-host ring buffer) with live chart and real p95 KPI.
- Foreground alert watcher (badge + snack on new firing alerts / failed CI runs).
- Structured cronjob last-run tracking (per-job log viewer, edit in place).
- APM-lite: agent v2 `/procstats` (top processes, per-port connections).
- Secure credentials: `flutter_secure_storage` with SharedPreferences migration.
- GitHub Projects v2 (GraphQL) Tasks tab with assigned-issue fallback.
- In-app updates from GitHub Releases (Windows/Linux/macOS).
- Streaming AI chat (SSE/NDJSON, Anthropic/Gemini-native, Ollama tool calling).
- AI audit trail (append-only, capped at 200, filter + history viewer).
- Log classifier, forecast alerts, anomaly baselines, chat grounding.
- Biometric app lock: `local_auth` + lock screen on cold start and
  resume-from-background when the Settings toggle is on, with device
  PIN/passcode fallback and clear messaging where nothing is available.

### Security
- Credential storage cut over to OS keychain/keystore; quality gates documented
  (`docs/quality-gates.md`); gitleaks + osv-scan enforced in CI.

## [1.0.0-alpha.1+1] — 2026-10-28

### Fixed
- macOS build: `List<dynamic>` → `List<double>` type error in
  latency/CPU history (#36).
- Linux release build: add `libsecret-1-dev` for
  `flutter_secure_storage` (#11).
- Release workflow action refs (valid checkout/flutter pins, tags for
  the rest) (#10).
- README: wire real screenshots (overview + server-details) (#12);
  broken image refs removed until PNGs landed (#9).

### Added
- Real SSH log tail (journal/syslog/docker per saved server, refresh on
  poll tick; demo heartbeat only with no servers).
- Metrics history with live p95 (per-host latency/CPU ring buffer,
  cap 120) and foreground alert watcher (bell + snack on new firing
  signals / failed CI runs, diffed against last-seen set) (#13).
- Secure credentials: `flutter_secure_storage` (Keychain/Keystore) with
  one-time `SharedPreferences` migration; APM-lite agent v2 `/procstats`
  (top processes, per-port connections); GitHub Projects v2 (GraphQL)
  Tasks tab; in-app updates from GitHub Releases (Windows/Linux/macOS);
  streaming AI chat (SSE/NDJSON, Anthropic/Gemini-native, Ollama tool
  calling); AI audit trail (append-only, capped at 200) (#8).

## Owner actions (repo settings this file cannot cover)

These need owner clicks in the GitHub web UI (or `gh repo edit`):

- [ ] **Social preview image** — Settings → General → Social preview → upload
      `assets/marketing/social/spotlight-1x1.png` (or `hero.png`, 1280×640+).
- [ ] **Homepage URL** — Set to the launch site/docs URL once live
      (`gh repo edit --homepage <url>`).
- [ ] **About description/topics** — already set (pitch-black IT Control Center
      + 9 topics); re-verify after launch.
- [ ] **First release tag** — cut `v0.1.0` to start versioned entries above;
      confirm `release.yml` artifacts attach correctly.

## Template for new entries (copy, fill, move above)

```markdown
## [x.y.z+n] — YYYY-MM-DD

### Added

- …

### Changed

- …

### Fixed

- …

### Security

- …

### Docs

- …

### Removed / Deprecated

- …
```

Keep one section per heading actually used; drop the rest. Link PR/issue
numbers (`#13`) so any entry traces back to the change.
