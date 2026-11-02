# Incident runbook (bad release, outage, security)

Severity first, heroics never. One commander (DevOps unless Sofia takes
it), one notes thread, everything else waits its turn.

## Severity

| Sev | Meaning | Example |
|---|---|---|
| S1 | Users losing data / credentials exposed | keychain leak, updater serving malware |
| S2 | Release unusable for most | crash on launch on a platform, gate bypassed |
| S3 | Degraded but working | beta-only regression, dashboard gap |

## First 15 minutes (all sevs)

1. **Stop the bleeding**: bad release → `tool/rollback_release.py`
   (dry-run, then `--execute`) per `docs/runbooks/rollout.md`. Bad
   deploy elsewhere → `docs/runbooks/agent-lifecycle.md --rollback`.
   Suspected secret leak → rotate first (`docs/runbooks/secrets-hardening.md`),
   investigate second.
2. **Declare**: one message — sev, what broke, who's commanding, where
   notes live. Update every 30 min (S1/S2) or 2 h (S3).
3. **Preserve evidence**: release-proof.json, SBOM, build-info, Sentry
   issue link, `SHA256SUMS.txt`. Do not delete the bad release until the
   note records its asset hashes (audit trail).

## Next (S1/S2)

- Reproduce on the pinned toolchain (`docs/release-process.md`) — "works
  on my machine" on a different Flutter is not evidence.
- Bisect by track: beta-only → block promotion, fix forward. Stable →
  rollback first, root-cause second.
- Crash spike? Sentry Issues filtered to the release; attach the issue
  URL to the incident note.

## Close-out (all sevs, within 48 h)

- [ ] Incident note filed: timeline, sev, impact (# users / releases),
      root cause, what stopped the bleeding, links (proof bundle, Sentry).
- [ ] Follow-up card(s) created (assignee + milestone, not "someone
      should…"). A fix-forward gets a new tag number — never reuse the
      bad one.
- [ ] If the beta gate missed it: propose a new C-check to Burhanah
      (Release Verifier owns `tool/verify_release.py`) instead of
      bolting on a side check.
- [ ] If rollout mechanics caused it: fix `docs/runbooks/rollout.md`
      and the workflow in the same PR as the lesson.

## What NOT to do

- Never retag, never force-push, never delete-then-recreate a release
  to "make it clean" — the tag history is the audit trail.
- Never page for beta-track signals (see alert routing in
  `docs/observability-dashboards.md`).
- Never commit secrets, tokens, or DSNs while firefighting — the repo
  is public and gitleaks is watching.
