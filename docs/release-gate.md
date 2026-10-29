# Release gate + v1 acceptance criteria

No release ships until every box below is checked. The gate applies to
v1-ship (milestone
[v1-ship](https://github.com/alfirus/mycontrolpanel/milestone/1)) and stays
in force for later releases.

## Gate: static checks

- [ ] `flutter analyze` — zero issues.
- [ ] `flutter test` — full suite green.
- [ ] Security workflow green (`.github/workflows/security.yml`).

## Gate: builds

- [ ] Release builds succeed on all five targets: macOS, Windows, Linux,
      Android (APK), iOS (IPA — macOS + Xcode).
- [ ] In-app update path verified (Windows/Linux/macOS against a draft
      GitHub Release).

## Gate: live-data acceptance (v1 bar — no MOCK-tab ships as live)

- [ ] Server metrics (CPU/RAM/disk, latency, uptime) populate from the
      `:9108` agent on a real server — no demo fallback when connected.
- [ ] Cronjobs discovered live (`crontab`, `/etc/crontab`, `/etc/cron.d/*`).
- [ ] Apps discovered live (systemd, Docker, listening ports).
- [ ] Alerts harvest live (failed units, disk ≥80/90%, brute-force, load,
      kernel errors, reboots).
- [ ] GitHub tab: live issues/PRs/Tasks over PAT, or an explicit
      demo-mode banner when no token is configured.
- [ ] GitLab tab: live data over PAT, or an explicit demo-mode banner.
- [ ] CI/CD tab: live runs, or an explicit demo-mode banner.
- [ ] Security tab: live findings, or an explicit demo-mode banner.
- [ ] Log tail streams live over SSH (no simulated stream in release).
- [ ] AI chatbox labels its replies (live vs local/demo) honestly.

## Gate: credentials

- [ ] Fresh install: secrets land in the OS keychain/keystore
      (`SecureStore`), never plaintext in prefs.
- [ ] Upgrade: legacy prefs-resident secrets migrate once via
      `migrateIfNeeded()` and remain working (see
      `decisions/001-credential-storage.md`).

## Gate: docs & hygiene

- [ ] README screenshots match the current UI.
- [ ] README roadmap reflects the shipped scope; Done section updated.
- [ ] One-click metrics-agent install verified against a real server
      (install + `GET /metrics` + systemd unit running).

## Sign-off

Gate checked by: ________  Date: ________
CEO (Sofia) release approval: ________
