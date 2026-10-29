# Changelog — MyControlPanel

All notable changes to this project are recorded here, newest first.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
releases are cut as Git tags `v<name>` via `.github/workflows/release.yml`
(see [Release checklist](docs/releases.md)).

## [Unreleased]

### Added
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
