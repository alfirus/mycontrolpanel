# Decision 001 (PROPOSAL — needs owner sign-off): Mandate `flutter_secure_storage` for all credentials

Status: **proposed** — not final until the owner approves.
Label: `need-owner-decision`.

## Context

PR #8 landed `lib/services/secure_store.dart` (`SecureStore`): secrets live in
the OS keychain/keystore, `SharedPreferences` keeps only `secure:<key>`
markers, and a one-time idempotent migration (`migrateIfNeeded`) moves legacy
prefs-resident secrets (server credentials, `github_token`, `gitlab_token`,
`ai_key`) into secure storage. `pubspec.yaml` already depends on
`flutter_secure_storage: ^11.2.0`, and the Linux release build installs
`libsecret-1-dev` (PR #11).

But two things are still open:

1. The README still tells users credentials "are stored locally via
   `SharedPreferences`" — stale and misleading (fixed in this PR).
2. `SecureStore.readServers()` still falls back to raw prefs values when a
   secure read misses — i.e. plaintext credentials remain a supported path.

## Proposal

1. **Mandate `flutter_secure_storage` (Keychain/Keystore/libsecret) as the only
   credential store** for server passwords/keys, PATs, and AI keys.
2. **Remove the raw-value fallback** in `readServers()` after one confirmed
   migration cycle: a missing secure entry resolves to empty (force re-entry),
   never to a plaintext prefs read.
3. **Verify the migration in the release gate** (`docs/release-gate.md`):
   fresh-install and upgrade-from-plaintext paths both covered.

## Owner question

@alfirus — please approve or reject:

- (a) secure storage as the mandatory standard, and
- (b) removing the plaintext prefs fallback (vs keeping it as a safety net).

On approval this note moves to **accepted** and (b) becomes a v1-ship code task.
