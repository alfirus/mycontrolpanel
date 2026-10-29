# Contributing to MyControlPanel

This repo is PUBLIC (MIT-track, see the packaging decision PR). Never commit
secrets, tokens, keys, or customer data — CI runs gitleaks on full history
with zero tolerance.

## Setup

```bash
flutter --version   # stable channel
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

No backend to run: live services degrade to `Mock*` fixtures under
`MCP_MOCKS=true` (see `lib/services/mock_services.dart`).

## Branching (hard rules)

- One feature branch per contribution: `feat/<short-name>`.
- One PR per contribution against `main`.
- NEVER push `main` directly. Keep the branch up to date
  (`git merge origin/main`) so the merge queue stays green.

## Definition of done (PR checklist)

Required CI before merge — these are branch-protection checks:

| gate | workflow → job | command |
|---|---|---|
| unit/widget tests | `ci.yml` → `test` | `flutter test` |
| static analysis | `security.yml` → `analyze` | `flutter analyze --no-fatal-infos --no-fatal-warnings` |
| dependency scan | `security.yml` → `osv-scan` | OSV over `pubspec.lock` |
| secret scan | `security.yml` → `gitleaks` | full-history scan |
| compile matrix | `build-matrix.yml` | desktop/mobile smoke builds per PR |

For anything touching secrets, SSH, or the agent protocol, answer the
review checklist in `docs/quality-gates.md` §3 inside the PR body:

- Secrets: nothing new in SharedPreferences / logs / comments —
  keychain markers (`secure:`) only, via `SecureStore`.
- Agent protocol: new wire fields optional + ignored by old readers;
  `kMinAgentVersion` floor respected.
- Mocks: new service covered by a `Mock*` + `MCP_MOCKS` path.
- Specs + tests updated (`docs/specs/`, `test/`).

Full gate reference: `docs/quality-gates.md`.
Release tagging + publishing: `docs/release-process.md` (tags are an
owner-held step — do not cut release tags from a feature PR).

## Secrets (non-negotiable)

- Server credentials, API tokens (`github_token`, `gitlab_token`,
  `ai_key`), agent tokens, SSH key material: OS keychain via
  `lib/services/secure_store.dart`. SharedPreferences holds UI prefs
  and `secure:` markers only.
- `test/secure_prefs_guard_test.dart` enforces this in CI — if it fails,
  reroute through `SecureStore`, do not weaken the test.
- Logs/crash reports: run entries through `SecretHygiene.redactForLog`.

## Agent changes

The :9108 agent source of truth is `AgentService.agentScript` in the app;
`agent/mcp-agent.service` is the hardened systemd reference. Keep `ExecStart`
and paths in sync. Install/upgrade flow: `scripts/install-agent.sh`
(+ `docs/runbooks/agent-lifecycle.md`); reliability notes:
`docs/runbooks/agent-reliability.md`.

## Who owns what

| area | owner |
|---|---|
| Delivery / milestones | Maisarah (eng manager) |
| GitHub API + Actions, app UI | Elizabeth (+ Nurul UI, + Lisa shapes) |
| Security review | Alya |
| QA / mock-gap walkthroughs | Balqis |
| CI / releases / ops | Aisyah (+ Shiela: GitHub automation) |
| Roadmap / status cadence | Rina |
| Docs | Ain |
