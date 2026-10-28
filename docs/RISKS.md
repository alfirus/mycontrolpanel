# MyControlPanel Dependency + Risk Register

Owner: Rina (PM) · Updated: 2026-10-28 · Review: each milestone close.
Severity: H = blocks release · M = degrades / needs mitigation · L = watch.

## 1. Metrics agent on `:9108` (H)

- **What:** stdlib-only Python agent, installed as systemd unit via one-click
  SSH; app verifies `GET /metrics`, v2 adds `/procstats`. Plain HTTP on a
  fixed port, no auth (AgentService.agentPort = 9108, agentVersion = 2).
- **Risks:** unauthenticated HTTP on LAN — anyone who can reach `:9108` reads
  CPU/RAM/process/port data; agent has no TLS, no token, no IP allowlist.
  Fixed port collides if the host already serves 9108. Agent v2 parsing
  (`/proc`, `os.getloadavg` fallback) is best-effort and untested on
  non-systemd / non-Linux hosts (macOS, BSD, containers without `/proc`).
  Install path assumes systemd + password/key SSH; failures leave a
  half-installed unit.
- **Mitigation:** Phase 1 — bind agent to localhost + SSH-tunnel instead of
  open port, or add shared-secret header; document firewall expectation.
  Phase 2 — install health-check + rollback on failed verify; add agent
  self-update story. Tracked via #20 (alert polling) and #22 (storage audit).

## 2. `dartssh2` SSH layer (H)

- **What:** all live data (metrics fallback, cron/app/alert discovery,
  terminal, agent install) rides `dartssh2 ^4.1.0` sessions.
- **Risks:** single-point-of-failure dependency — an API break or unresolved
  vulnerability in dartssh2 grounds every live feature at once (OSV scan in
  `security.yml` covers `pubspec.lock`, but OSV data lags for niche Dart
  packages). Long-lived sessions + polling loops risk battery drain and
  stale-connection errors; host-key verification policy is a trust decision
  (TOFU vs pinning) with security UX consequences. Encrypted-key support lives
  in `ssh_key_loader.dart` — passphrase handling must never touch prefs.
- **Mitigation:** pin versions, review `flutter pub outdated` + OSV output
  weekly (STATUS.md cadence); add reconnect/backoff + session timeout tests;
  keep passphrases memory-only, audit in #22.

## 3. Credential storage: SharedPreferences → SecureStore (M, was H)

- **What:** secrets now in OS Keychain/Keystore via `flutter_secure_storage`
  (`SecureStore`), prefs JSON holds `secure:` markers; one-time migration
  guarded by `secrets_migrated_v1` flag; best-effort, never throws.
- **Residual risks:** migration is best-effort — a crash mid-migration can
  strand a server on the prefs copy or orphan a keychain entry; the flag
  means a partial run never retries. Linux needs `libsecret-1-dev`
  (fixed in #11 — must stay in release notes or Linux installs break).
  PATs/AI keys added later may bypass `SecureStore` if new code writes prefs
  directly — needs the #22 audit + a review rule (new secret fields go
  through `SecureStore`, enforced at PR review).
- **Mitigation:** #22 acceptance criteria cover re-running migration safely,
  Linux dep docs, and the audit.STATUS.md release checklist re-verifies.

## 4. GitHub API surface (M)

- **What:** REST via `GithubService` (classic/fine-grained PAT, `repo`
  scope) + Projects v2 GraphQL for Tasks tab; in-app updates read Releases.
- **Risks:** PAT with `repo` scope is a powerful secret — leak = code access;
  stored token scope creep over time. Rate limits (60/h unauth, 5000/h auth)
  can blank the GitHub/CI tabs with no cached fallback. GraphQL Projects v2
  queries break silently on schema change. Release-asset names must match
  `release.yml` exactly or the updater 404s.
- **Mitigation:** least-privilege fine-grained tokens documented in Settings;
  token via SecureStore (#16); cached last-good state + friendly rate-limit
  UI; updater asset-name check in release checklist (STATUS.md).

## 5. Actions CI/CD + release pipeline (M)

- **What:** `security.yml` gate (analyze + OSV + gitleaks, required checks on
  main) and `release.yml` (tag-triggered desktop builds + SHA256SUMS).
- **Risks:** history shows the pipeline needed three fixes in two days
  (#10 action refs, #11 Linux secret dep) — release path is fragile and only
  exercised on tags. No mobile artifacts (apk/ipa) in `release.yml` yet the
  README lists `flutter build apk/ipa` — expectation gap. macOS sandbox
  entitlements (network.client + picker-only key import) can regress with
  Xcode updates (README pins Xcode 15+/macOS 12.0, pods forced).
- **Mitigation:** dry-run `release.yml` via workflow_dispatch before each
  milestone tag; STATUS.md checklist includes Linux-dep + sandbox + asset-name
  verification; mobile artifacts explicitly scoped post-1.0.

## 6. Platform/volume risks (L)

- Mock-to-live conversions (#16/#18) can regress demo mode — keep a
  deterministic demo dataset for screenshots and first-run UX.
- Notification/lock features (beta.1) face per-OS background limits;
  design-first per #20 follow-up. AI chat mock replies must stay clearly
  labelled until a real provider is wired (hallucination liability).

## Top-3 watch list (for weekly STATUS.md)

1. Agent `:9108` unauthenticated HTTP — needs localhost/tunnel or token story.
2. `dartssh2` single-point-of-failure — weekly OSV/outdated review.
3. Release pipeline fragility — dispatch dry-run before every tag.
