# Release process (versioning, matrix, signing, tagged releases)

This is the DevOps companion to `release.yml` (tag-gated desktop builds +
GitHub Release publish) and `build-matrix.yml` (PR-time smoke builds).
`ci.yml` + `security.yml` remain the merge gates; nothing here changes them.

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
| Windows | `flutter build windows`, artifact 7d | `.zip` published | Unsigned; MSIX/Authenticode enrollment is a manual owner step |
| macOS | `flutter build macos`, artifact 7d | `.zip` (ditto) published | Unsigned; Apple notarization needs owner-held Developer ID |
| Linux | analyze+test only (see note) | `.tar.gz` published | SHA256SUMS checksum |
| Android | `flutter build apk --release` (debug-signed), artifact 7d | Not published yet | Debug-signed smoke only; Play keystore is a manual owner step |
| iOS | `flutter build ios --no-codesign` | Not published yet | No signing in CI; provisioning is a manual owner step |

Linux note: a full Linux desktop build needs `apt-get install` of GTK
toolchains (privileged, sudo). Per repo policy there are no sudo steps in
PR CI, so PR coverage for Linux is analyze+test and the real Linux build
runs tag-gated in `release.yml`. Do not add `sudo apt-get` to PR workflows.

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
