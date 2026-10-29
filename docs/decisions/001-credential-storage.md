# Decision 001 (ACCEPTED — owner-mandated): Full migration to `flutter_secure_storage`

Status: **accepted** — owner ruling 2026-10-28 (Option A MANDATED).
Supersedes the earlier proposal framing; no further sign-off needed.

## Context

PR #8 landed `lib/services/secure_store.dart` (`SecureStore`): secrets live in
the OS keychain/keystore, `SharedPreferences` keeps only `secure:<key>`
markers, and a one-time idempotent migration (`migrateIfNeeded`, called at
startup in `control_center_screen.dart` and `settings_screen.dart`) moves
legacy prefs-resident secrets (server credentials, `github_token`,
`gitlab_token`, `ai_key`) into secure storage. `pubspec.yaml` depends on
`flutter_secure_storage: ^11.2.0`; Linux release builds install
`libsecret-1-dev` (PR #11).

## Decision (owner, 2026-10-28)

**Option A — full migration of server passwords/keys/tokens from
SharedPreferences to `flutter_secure_storage`.** Implemented as decided:

1. `flutter_secure_storage` (Keychain/Keystore/libsecret) is the only
   credential store for server passwords/keys, PATs, and AI keys.
2. No plaintext-credential read path remains: `readServers()` heals any legacy
   raw prefs value on the spot (moves it into the keychain, persists only the
   `secure:` marker, keeps the secret in memory for that session only), and a
   missing secure entry resolves to empty (force re-entry).
3. Migration verified in the release gate (`docs/release-gate.md`):
   fresh-install and upgrade-from-plaintext paths both covered.

The README now documents OS-keychain storage (stale SharedPreferences claim
removed in this PR).
