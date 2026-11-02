# Staged rollout: beta / stable tracks, promotion, rollback

Two tracks, one pipeline (`.github/workflows/release.yml`).

## Tag convention

| Tag shape | Track | GitHub flag | Environment | Gate |
|---|---|---|---|---|
| `v1.0.0-alpha.N`, `v1.0.0-beta.N` | beta | `prerelease: true` | `release-beta` (auto, no approvals) | Burhanah's verify-gate (binding) |
| `v1.0.0` (clean) | stable | `prerelease: false` | `release-stable` (owner adds required reviewers) | verify-gate + human approval |

The publish job selects the environment from the tag shape
(`contains(tag, '-')`), so the wiring never changes — adding required
reviewers to `release-stable` in repo Settings → Environments is what
turns stable into a manual promotion. Until then both tracks publish
automatically once the gate is GO.

## Cutting a beta

1. Bump `version:` in `pubspec.yaml` to `1.0.0-beta.N+<build>`, CHANGELOG
   entry with date (C1 in `tool/verify_release.py` pins all three).
2. PR to main, gates green, merge.
3. `git tag v1.0.0-beta.N && git push origin v1.0.0-beta.N`.
4. Watch `release`: 4 builds + SBOM + verify-gate, then publish to the
   `release-beta` environment. Release name carries `(beta)`.
5. The beta-track in-app updater (`UpdateChannel.beta`, opt-in in
   Settings) offers it; stable users never see it.

## Promoting beta → stable

1. Bake time + crash-free looks clean on the observability dashboards
   (`docs/observability-dashboards.md`).
2. Bump `version:` to the clean `1.0.0+<build>`, CHANGELOG entry.
3. PR → merge → `git tag v1.0.0 && git push origin v1.0.0`.
4. `release` runs the full train again (builds are rebuilt, never
   re-uploaded) and pauses at `release-stable` for owner approval.
5. Approve in Actions → publish. Release name carries `(stable)`.
   Stable updaters (`/releases/latest`) pick it up.

## Rollback (bad release on either track)

Policy: tags never move, releases are never force-pushed. The updater
follows `/releases/latest` (stable) or the newest non-draft (beta), so
rollback = make the bad release invisible to those endpoints:

```sh
# Dry-run first, always:
python3 tool/rollback_release.py --bad-tag v1.0.0-beta.2 --last-good v1.0.0-beta.1
# Stable track:
python3 tool/rollback_release.py --bad-tag v1.0.0 --last-good v1.0.0-beta.3 --stable
# Execute (runs gh):
python3 tool/rollback_release.py --bad-tag v1.0.0-beta.2 --last-good v1.0.0-beta.1 --execute
```

What the tool does: drafts (or deletes, keeping the tag) the bad
release, verifies the last-good release still carries the full updater
asset set, and reminds you to file the incident note
(`docs/runbooks/incident.md`). Then cut a NEW tag with the fix — never
reuse the bad number.

## Owner setup checklist (Sofia)

- [ ] Create environments `release-beta` (no protection) and
      `release-stable` (required reviewers: Sofia + one more).
- [ ] Decide the beta bake window (default: 7 crash-free days at 99.5%).
- [ ] After the first stable: confirm the in-app updater offers it on
      Windows/macOS/Linux before announcing.
