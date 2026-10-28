# Release Checklist

How to cut a release. Every `v*` tag builds macOS / Windows / Linux
artifacts via `.github/workflows/release.yml` and must pass this list
first. The full v1 acceptance bar (no MOCK-tab ships as live, credential
rules) is the release gate in `docs/release-gate.md` (PR #30, in review)
— this page is the mechanical runbook; the gate is the quality bar.

## 1. Prepare

- [ ] `CHANGELOG.md` `[Unreleased]` section filled in (Added / Changed /
      Fixed / Security / Docs / Removed) with PR numbers; retitled to the
      new version + date.
- [ ] `pubspec.yaml` `version: <name>+<build>` bumped to match the tag.
- [ ] README screenshots match the current UI; README roadmap/Done
      section reflects the shipped scope.
- [ ] Docs touched by the release re-verified: agent API
      (`docs/agent-api.md`), setup (`docs/setup.md`), live-vs-mock
      matrix (`docs/roadmap.md`).

## 2. Verify

- [ ] `flutter analyze` — zero issues.
- [ ] `flutter test` — full suite green.
- [ ] Security workflow green (`.github/workflows/security.yml`).
- [ ] One-click metrics-agent install verified against a real server
      (install + `GET /metrics` + systemd unit running).

## 3. Cut

```bash
git tag v1.0.0-alpha.2 && git push origin v1.0.0-alpha.2
```

- [ ] Tag pushed; `release.yml` run green on all three OS runners.
- [ ] Release assets present with exact updater-expected names:
      `mycontrolpanel-macos-<version>.zip`,
      `mycontrolpanel-windows-<version>.zip`,
      `mycontrolpanel-linux-<version>.tar.gz`, plus `SHA256SUMS.txt`.
- [ ] In-app update path spot-checked (Windows/Linux/macOS against the
      new GitHub Release).
- [ ] GitHub Release notes pasted from the `CHANGELOG.md` entry.

## 4. After

- [ ] New `[Unreleased]` section opened at the top of `CHANGELOG.md`.
- [ ] Rina's roadmap / STATUS burndown updated for the closed milestone
      (PR #15 / PR #31 when merged).
- [ ] Announce: what went live, what is still mock, where to report
      issues.

## Versioning rules

- Pre-1.0: `1.0.0-alpha.N` (mock-killing) → `1.0.0-beta.1` (background +
  lock) → `1.0.0` (hardened). See Rina's phased roadmap.
- Every tag is `v<version-name>` (e.g. `v1.0.0-alpha.2`); the workflow
  strips the `v` for asset names.
- Never retag: a bad release gets a new number, not a force-push.
