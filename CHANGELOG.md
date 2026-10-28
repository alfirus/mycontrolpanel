# Changelog — MyControlPanel

All notable changes to this project are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/) once tagged
(no release tags cut yet — see Owner actions below).

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

### Security
- Credential storage cut over to OS keychain/keystore; quality gates documented
  (`docs/quality-gates.md`); gitleaks + osv-scan enforced in CI.

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
