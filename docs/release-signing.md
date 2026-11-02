# Release signing — owner enrollment guide

Status: **scaffolding live, no secrets enrolled.** All signing steps in
`.github/workflows/release.yml` are conditional: they run only when the
named secrets exist, and are skipped otherwise. Unenrolled tag builds ship
unsigned, exactly as before. Nothing here changes PR CI.

## Where the secrets live

GitHub **Environment** named `release-signing` (repo Settings →
Environments). Environment secrets — NOT repository secrets, NOT in code:

| Secret | Used by | Format |
|---|---|---|
| `ANDROID_KEYSTORE_B64` | Android leg: `android/key.properties` materialization | base64 of the Play upload keystore (`.jks`) |
| `ANDROID_KEY_ALIAS` | same | key alias string |
| `ANDROID_KEY_PASSWORD` | same | key password |
| `ANDROID_STORE_PASSWORD` | same | keystore password |
| `WINDOWS_CERT_B64` | Windows leg: Authenticode `signtool` | base64 of the code-signing `.pfx` |
| `WINDOWS_CERT_PASSWORD` | same | PFX password |
| `APPLE_CERT_B64` | macOS leg: `codesign` | base64 of the Developer ID `.p12` |
| `APPLE_CERT_PASSWORD` | same | p12 password |
| `APPLE_NOTARY_ID` | macOS leg (notarization, future) | Apple ID email |
| `APPLE_TEAM_ID` | same | 10-char Team ID |
| `APPLE_NOTARY_PASSWORD` | same | app-specific password |

Generate the base64 blobs locally, never commit them:

```sh
base64 -w0 release-keystore.jks   # paste into ANDROID_KEYSTORE_B64
base64 -w0 release-cert.pfx       # paste into WINDOWS_CERT_B64
base64 -w0 developer-id.p12       # paste into APPLE_CERT_B64
```

`.gitignore` already blocks `android/key.properties`, `*.jks`,
`*.keystore`, `*.p12`, `*.pfx`, `*.mobileprovision`.

## How enrollment changes a tag build

1. **Android**: CI writes `android/key.properties` + `release.jks` before
   the build; `android/app/build.gradle.kts` signs with the enrolled
   keystore. Without enrollment the debug key is used (unchanged).
2. **Windows**: CI signs every `.exe`/`.dll` in the runner output with
   `signtool` (SHA-256 + RFC 3161 timestamp) BEFORE the zip is packaged,
   so the published zip carries Authenticode signatures.
3. **macOS**: CI `codesign --deep --options runtime`s the `.app` BEFORE
   the ditto zip, then verifies. Notarization (`notarytool submit`,
   staple) is the owner-triggered follow-up once the first signed build
   lands — see the manual step below.
4. **Linux**: no signing story (checksums only) — standard for tarballs.
5. **iOS**: not in the tag matrix (`flutter build ios --no-codesign` is
   PR smoke only); App Store provisioning stays a manual owner step.

The per-OS `build-info-<os>.json` receipt records whether the build was
signed (`"signed": true/false`), so any release is auditable after the
fact.

## Owner manual steps (Sofia)

- [ ] Create the `release-signing` environment; add the secrets above.
- [ ] Cut a `-beta` tag; confirm the `signed` flags flip to true in the
      published `build-info-*.json` files.
- [ ] macOS: run `xcrun notarytool submit <zip> --apple-id … --team-id …`
      once per release until staple-on-CI is wired (follow-up card).
- [ ] Windows: confirm SmartScreen reputation building (new certs warn
      until reputation accrues — expected, not a bug).

## Rotation

Replace the secret values in the environment; no code change needed. The
old blobs are unrecoverable from CI logs (only boolean `signed` flags are
ever printed).
