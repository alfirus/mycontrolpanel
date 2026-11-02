# Release gates — beta verifiable gate + proof bundle

Owner: Burhanah (Release Verifier). No beta/stable release ships on a
worker's summary alone: the gate re-runs the checks, reads the receipts,
and emits `release-proof.json`. `GO` / `HOLD` verdicts are binding on the
lane. No lead can overrule a HOLD — only the owner (via Sofia) can waive
one (§4).

This doc is the procedural half of the gate. The executable half is
`tool/verify_release.py` (stdlib-only) plus the `verify-gate` job in
`.github/workflows/release.yml`, which runs it as a required job:
`publish release` has `needs: [build, verify-gate]`, so a HOLD verdict
(non-zero exit) blocks the GitHub Release from being created.

## 1. Checks (C1–C6)

| id | name | what is re-verified (not trusted) |
|----|------|-------------------------------------|
| C1 | version==CHANGELOG==tag | `pubspec.yaml version:` name part, newest versioned `## [x]` CHANGELOG section (+ date), and the tag agree after stripping `v` / `+build` |
| C2 | all 3 platform assets fresh from CI | `dist/` holds `mycontrolpanel-macos-<v>.zip`, `mycontrolpanel-windows-<v>.zip`, `mycontrolpanel-linux-<v>.tar.gz` (exact updater names) + `SHA256SUMS.txt`; every hash re-computed and matched; mtimes within 24h (fresh from this run, not leftovers) |
| C3 | flutter test green | `flutter test` re-run in the gate job (exit 0), not the build jobs' logs |
| C4 | agent pytest green | `python -m pytest agent/tests -q` re-run (exit 0): agent install contract — port :9108, unit markers, installer defaults, app/payload endpoints |
| C5 | consent/Sentry default-off tests present | `test/sentry_consent_test.dart`, `test/background_consent_tile_test.dart`, `test/desktop_consent_tile_test.dart` exist and pin default-OFF; `lib/services/error_reporting.dart` keeps `?? false` |
| C6 | MIT headers intact | `LICENSE` carries MIT + Copyright; every `lib/**/*.dart` carries an SPDX-MIT header in its first 5 lines |

Any `SKIP` (e.g. a suite not re-run) counts as unverified and forces HOLD.
The gate never crashes green: a checker exception is recorded as FAIL.

## 2. Proof bundle (`release-proof.json`)

Emitted by the verifier on every gate run, uploaded as the
`release-proof-<tag>` workflow artifact (90-day retention), and attached
to the GitHub Release next to the assets:

```jsonc
{
  "schema": "mycontrolpanel/release-proof@1",
  "verdict": "GO | HOLD | GO-WAIVED",
  "tag": "v1.0.0-beta.1", "version": "1.0.0-beta.1",
  "commit": "<sha>", "timestamp_utc": "<iso>",
  "checks": [{"id": "C1", "name": "...", "status": "pass|fail|skip", "detail": "..."}],
  "assets": [{"name": "...", "sha256": "...", "size": 123}],
  "waiver": null | {"file": "docs/waivers/<tag>.md", "covers": ["C3"]}
}
```

Local reproduction (laptop has no flutter / no CI assets, so a local run
HOLDs on C2/C3 by design — that is the gate working, not a bug):

```bash
python3 tool/verify_release.py --tag v1.0.0-beta.1
python3 tool/verify_release.py --tag v1.0.0-beta.1 --skip-flutter --skip-assets  # triage only, still HOLD
```

## 3. Verdicts

- `GO` (exit 0) — all six checks pass on re-run evidence. Publish proceeds.
- `HOLD` (exit 1) — any FAIL or SKIP, with the specific reason printed per
  check and recorded in the proof. Publish is blocked. The lane fixes the
  cause, never the verdict: do not edit the proof file to clear a HOLD.
- `GO-WAIVED` (exit 0) — every non-passing check is covered by a valid
  owner waiver (§4). The waiver is embedded in the proof and must be
  quoted in the release notes.

## 4. Owner-waiver path (via Sofia, CEO only)

Some holds are judgment calls (e.g. shipping a beta with a known,
time-boxed flake while CI capacity is down). The waiver path keeps that
call with the owner, in writing, in-repo:

1. Author `docs/waivers/<tag>.md` containing all three lines:
   `Tag: <tag>`, `Approved-by: Sofia`, `Reason: <why + expiry/mitigation>`,
   plus one `Covers: <C-id>` line per waived check.
2. Merge the waiver file to main through the normal PR gates first.
3. Re-run the release workflow via `workflow_dispatch` with inputs
   `tag=<tag>` and `waiver=docs/waivers/<tag>.md`.
4. The gate validates the waiver (tag match + `Approved-by: Sofia` +
   `Reason:` present) and emits `GO-WAIVED`; anything else is still HOLD.
5. Paste the waiver reason into the GitHub Release notes.

No other approver string validates. A waiver covers exactly the checks its
`Covers:` lines name; uncovered FAILs still HOLD. Waivers expire with the
tag — they never carry forward.

## 5. Relationship to the other gates

- `docs/release-gate.md` — the v1 product acceptance bar (live-data rules,
  credentials, docs hygiene). Still in force; this beta gate does not
  replace it.
- `docs/releases.md` — the mechanical cut checklist (bump, tag, verify,
  announce). The gate automates its §2 verify list.
- `ci.yml` + `security.yml` + `build-matrix.yml` — PR merge gates. The
  release gate trusts none of their logs; it re-runs what it asserts.

Gate checked by: Burhanah  Date: 2026-11-02
CEO (Sofia) release approval: ________
