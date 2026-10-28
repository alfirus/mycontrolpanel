# Quality gates — lint / test / CI, review checklist, squad split

## 1. Gates (all must be green before merge to main)

| gate | workflow | what |
|---|---|---|
| analyze + test | `ci.yml` | `flutter analyze --no-fatal-infos --no-fatal-warnings`, then `flutter test` |
| static analysis (duplicate) | `security.yml` → `analyze` | same analyzer pass on PR + push (kept for the security job family) |
| dependency scan | `security.yml` → `osv-scan` | OSV scan of `pubspec.lock` |
| secret scan | `security.yml` → `gitleaks` | full-history leak scan — repo is PUBLIC, zero tolerance |
| release build | `release.yml` | tag-triggered desktop artifacts (not a PR gate) |

Branch protection on `main` should require `ci` + `security` checks.
One feature branch + one PR per contribution; **never push to main**.

## 2. Local pre-PR checklist (no excuses — run before `gh pr create`)

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

Plus the review checklist (§3) answered in the PR body for anything
touching secrets, SSH, or the agent protocol.

## 3. Review checklist

- [ ] Additive or precisely scoped? Unrelated refactors out.
- [ ] Secrets: nothing new in SharedPreferences / logs / comments?
  Keychain markers (`secure:`) only, never raw credentials.
- [ ] Agent protocol: new wire fields optional + ignored by old readers?
  Version floor (`kMinAgentVersion`) respected, stale → reinstall prompt?
- [ ] Errors typed (`AgentProtocolException`) on new paths; legacy
  null-tolerance kept where old callers still expect null?
- [ ] Mocks: new service covered by a `Mock*` + `MCP_MOCKS` path?
- [ ] Docs: spec updated (`docs/specs/`) for contract changes?
- [ ] Tests: new parsers/contracts have unit tests (`test/`)?

## 4. Squad task split — GitHub API + Actions timeline + alert polling

Downstream work builds on the protocol spec + service contracts
(`docs/specs/agent-protocol.md`, `docs/specs/service-layer.md`).

| stream | owner | scope |
|---|---|---|
| GitHub API wiring | Elizabeth (+ Nurul: UI) | Replace `GithubService` mock tabs (issues/PRs/tasks) with live REST + Projects v2 GraphQL; add `GithubRepo` contract + mock; token stays in keychain |
| Actions timeline | Elizabeth (+ Lisa: backend shape) | CI/CD + deployments timeline from Actions API; poll cadence + caching; offline fallback to last snapshot |
| Alert polling | Alya (+ Balqis: QA) | Foreground `AlertWatch` → typed poller via `AlertRepository`; severity mapping review; background polling stays out of scope (needs workmanager) |
| Service migration | Lisa | Move `AgentService.fetch*` call sites to `Services.current` one screen at a time (migration map in `service-layer.md`) |
| Security review | Alya | Token scopes (`repo` minimal?), keychain audit, public-repo secret hygiene sign-off per §3 |
| QA | Balqis | `MCP_MOCKS=true` walkthroughs, rotation/migration matrix (§3 of cutover doc), widget tests for new screens |

Ordering: contracts first (this PR set), then GitHub API + alert
polling in parallel, Actions timeline last (depends on GitHub auth +
caching patterns).
