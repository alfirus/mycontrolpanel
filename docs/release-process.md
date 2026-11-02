# Release process (versioning, matrix, signing, tagged releases)

This is the DevOps companion to `release.yml` (tag-gated desktop builds +
GitHub Release publish) and `build-matrix.yml` (PR-time smoke builds).
`ci.yml` + `security.yml` remain the merge gates; nothing here changes them.

## Toolchain pins (reproducible builders)

Every workflow pins its toolchain — no floating `stable`:

| Tool | Pin | Where |
|---|---|---|
| Flutter | `3.47.9` (Dart 3.13.7; latest stable 2026-10-29) | `flutter-version:` in `ci.yml`, `build-matrix.yml`, `security.yml`, `headless.yml`, `device-lab.yml`, `release.yml` |
| Python | `3.12` | `setup-python` in `release.yml` (verifier + SBOM are stdlib-only) |
| Java | Temurin `17` | `setup-java` in `build-matrix.yml` (Android) + `release.yml` (Android leg) |
| Actions | commit-SHA pins (`# vX` comment) | all `uses:` lines except `setup-java@v4` (matches `build-matrix.yml`) |

Bump procedure: edit every `flutter-version:` line (grep for
`pinned — bump procedure`), verify with one green PR, record the new
version + date in this table. `flutter --version` output per builder is
also captured into the published `build-info-<os>.json` receipts, so any
release is traceable to its exact toolchain after the fact.

## Supply chain: SBOM + hashes + provenance

- `tool/sbom.py` (stdlib-only) converts `pubspec.lock` into a CycloneDX 1.5
  SBOM (`sbom-<version>.cyclonedx.json`). Validated on every PR by the
  `build-matrix` gate (`--check`) and published + checksummed on every tag.
- `SHA256SUMS.txt` covers every shippable plus the SBOM and the
  `build-info-<os>.json` receipts. It is assembled twice from the same
  inputs: once in `verify-gate` (from per-builder `.asset.sha256`
  sidecars, so C2 checks builder-produced digests) and authoritatively in
  `publish`. The gate proof bundle (`release-proof.json`) is published as
  an audit receipt and never checksummed.
- Code signing is conditional on owner enrollment — see
  `docs/release-signing.md`. The `signed` flag in `build-info-<os>.json`
  shows whether a given release was signed.

## Versioning

- Single source of truth: `version:` in `pubspec.yaml`
  (currently `1.0.0-alpha.1+1` — pre-release, no paid tiers through v1).
- A release is cut by pushing a tag: `git tag v1.0.0-alpha.1 && git push origin v1.0.0-alpha.1`
- Tag MUST match pubspec: tag `v<version>` where `<version>` is the part
  before `+` (e.g. tag `v1.0.0-alpha.1` for `1.0.0-alpha.1+1`).
  `release.yml` resolves the version from the tag name.
- The in-app updater (`lib/services/update_service.dart`) expects exactly:
  `mycontrolpanel-macos-<version>.zip`,
  `mycontrolpanel-windows-<version>.zip`,
  `mycontrolpanel-linux-<version>.tar.gz`, plus `SHA256SUMS.txt`.
  Do not rename assets without updating the updater + this doc.

## Platform matrix

| Platform | PR smoke build (`build-matrix.yml`) | Tag release (`release.yml`) | Signing |
|---|---|---|---|
| Windows | `flutter build windows`, artifact 7d | `.zip` published | Unsigned until owner enrolls; then Authenticode via `release-signing` env (see `docs/release-signing.md`) |
| macOS | `flutter build macos`, artifact 7d | `.zip` (ditto) published | Unsigned until owner enrolls; then Developer ID `codesign` via `release-signing` env |
| Linux | analyze+test only (see note) | `.tar.gz` published | SHA256SUMS checksum (no signing story for tarballs) |
| Android | `flutter build apk --release` (debug-signed), artifact 7d | `.apk` published (sideload / store track) | Debug key until owner enrolls; then Play keystore via `release-signing` env + `android/key.properties` |
| iOS | `flutter build ios --no-codesign` | Not published (no distributable without export) | No signing in CI; provisioning is a manual owner step |

Linux note: a full Linux desktop build needs `apt-get install` of GTK
toolchains (privileged, sudo). Per repo policy there are no sudo steps in
PR CI, so PR coverage for Linux is analyze+test and the real Linux build
runs tag-gated in `release.yml`. Do not add `sudo apt-get` to PR workflows.

## Staged rollout (beta / stable tracks)

Full runbook: `docs/runbooks/rollout.md`. Summary: tags with `-`
(`v1.0.0-beta.N`) publish through the `release-beta` environment
(automatic); clean `vX.Y.Z` tags pause at `release-stable` for owner
approval (configure required reviewers in repo Settings → Environments).
The in-app updater defaults to stable and only offers pre-releases on
the opt-in beta channel (`UpdateChannel` in
`lib/services/update_service.dart`). Rollback never moves tags:
`tool/rollback_release.py` drafts the bad release so the track endpoint
resolves to last-good, then cut a new tag with the fix.

## Tagged-release checklist

1. Bump `version:` in `pubspec.yaml`, commit to main via PR (gates must be green).
2. `git tag v<version> && git push origin v<version>`.
3. Watch the `release` workflow: build (macos/windows/linux) then publish.
4. Verify assets + `SHA256SUMS.txt` on the GitHub Release page.
5. In-app updater picks up `releases/latest` automatically (desktop only).

`workflow_dispatch` with input `tag` rebuilds an existing tag without moving it.

## Privileged / manual steps (never in CI)

- Linux build dependencies (`sudo apt-get install clang cmake ...`) — runs
  only inside tag-gated `release.yml`, approved by tagging.
- Apple Developer ID notarization, Windows Authenticode/MSIX, Play Store
  keystore, App Store provisioning — all need owner-held secrets and stay
  manual until the owner enrolls them (label such PRs `need-owner-decision`).
- Agent host steps (systemd install, firewall for TCP 9108) — see
  `docs/runbooks/agent-lifecycle.md`.
