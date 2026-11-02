# Release train runbook (cut → bake → promote → observe)

The human rhythm around the automated train (`release.yml` + Burhanah's
gate + staged environments). Mechanics (commands, tags, environments)
live in `docs/runbooks/rollout.md`; this page is the *who does what when*.

## Roles

| Step | Who | What |
|---|---|---|
| Cut beta | DevOps (Aisyah) | bump `version:`, CHANGELOG, PR, tag on green |
| Bake | Everyone | use the beta; report issues on the milestone card |
| Gate | Release Verifier (Burhanah) | GO/HOLD verdict is binding; HOLD needs Sofia waiver |
| Promote | Sofia (owner) | approve `release-stable`, announce |
| Observe | DevOps | dashboards in `docs/observability-dashboards.md` for 7 days |
| Roll back | DevOps | `tool/rollback_release.py`, then incident note |

## Cadence

- **Beta cut**: any weekday morning (so the full bake day is staffed).
  Never cut on Friday — an unobserved weekend beta teaches nothing.
- **Bake window**: minimum 7 crash-free days at ≥ 99.5% before a stable
  promotion (beta SLO is advisory, not paging).
- **Stable**: promote only on a weekday morning; keep the previous stable
  assets published for 14 days (the updater has no downgrade path, so the
  old release is the lifeboat).

## Pre-tag checklist (in addition to `docs/releases.md`)

- [ ] `flutter --version` matches the pinned toolchain in
      `docs/release-process.md` (or the pin PR lands first).
- [ ] `python3 tool/sbom.py --lockfile pubspec.lock --check` passes.
- [ ] CHANGELOG newest versioned section carries the tag version + date
      (C1 fails the gate otherwise).
- [ ] No open `need-owner-decision` blockers (signing, store, pricing).

## After publish

1. Confirm all six assets + `SHA256SUMS.txt` + SBOM + build-info on the
   GitHub Release page (names carry `(beta)`/`(stable)`).
2. Check the Sentry release appeared (or note that credentials are still
   unenrolled — the train does not depend on it).
3. Watch the rollout census (heartbeat Discover query) for 48 h: beta
   installs > 0 before any promotion talk.
4. Stable: spot-check the in-app updater on Windows/macOS/Linux, then
   announce (what's live, what's still mock, where to report issues).
