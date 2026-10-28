# Secure-credentials cutover — execution record (Option A, MANDATED)

Owner ruling 2026-10-28: the SharedPreferences → flutter_secure_storage
cutover is **mandated (Option A)**, not a proposal. This doc records the
executed cutover. Code: `lib/services/secure_store.dart` (`SecureStore`).

## 1. Target state (now enforced)

| data | store |
|---|---|
| server credentials (password / key / token) | OS keychain/keystore via `SecureStore`, key `srv_cred_<serverId>`; prefs JSON holds only `secure:<key>` markers |
| `github_token`, `gitlab_token`, `ai_key` | keychain (`SecureStore.readSecret/writeSecret/deleteSecret`) |
| UI prefs (theme, refresh, filters, metrics history, audit log) | SharedPreferences (non-secret, stays) |

## 2. What this change executes

1. **One-time migration** `SecureStore.migrateIfNeeded()` — idempotent,
   flag-guarded (`secrets_migrated_v1`), best-effort: moves embedded
   creds + standalone tokens to the keychain, rewrites prefs masked.
   Called on startup paths (settings + control-center init).
2. **Key rotation** `SecureStore.rotateServerCredential(id, newCred)` —
   overwrites the keychain entry in place; masked prefs JSON untouched.
   Operator flow: edit server → save → `writeServers` re-keys; or call
   rotate directly after a suspected leak, then restart the app.
3. **Orphan pruning** `SecureStore.pruneServerCredentials(validIds)` —
   deletes `srv_cred_*` entries with no matching server (post-import,
   post-delete hygiene).
4. **Delete paths close the loop**: single-server delete already removed
   the keychain entry; **clear-all now deletes every server's keychain
   entry before wiping the list** (was leaking secrets in the keychain).
5. **Stale copy corrected**: Settings footer + tagline claimed secrets
   live in SharedPreferences and told users to "move to secure storage
   for production" — both now state the keychain truth. `pubspec.yaml`
   "private packages" comment fixed: the repo is PUBLIC, so no secret
   may ever be committed.

## 3. Verification (reviewer / QA)

- [ ] Fresh install → add password server → inspect prefs XML:
  `server_connections` contains `secure:srv_cred_*`, no plaintext.
- [ ] Upgrade path: prefs with raw `credential` → launch →
  `migrateIfNeeded` masks it; token keys removed from prefs.
- [ ] Delete server → `srv_cred_<id>` gone from keychain.
- [ ] Clear-all → zero `srv_cred_*` entries remain.
- [ ] Rotate → new credential authenticates, old does not.
- [ ] `flutter analyze` clean; gitleaks clean (public repo — CI enforces).

## 4. Non-goals

- No remote vault / cloud sync: secrets stay on-device by design.
- No biometric gate on read (tracked separately; `biometrics` pref exists).
- Metrics history / audit log stay in SharedPreferences (non-secret).
