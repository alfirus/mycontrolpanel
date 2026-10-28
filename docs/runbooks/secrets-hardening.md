# Secrets-hardening runbook (toward flutter_secure_storage)

Decision context: `docs/decisions/001-credential-storage.md` mandates
Option A — full migration to `flutter_secure_storage` (Alya owns the
cutover execution; this runbook is the DevOps companion, not a second
implementation).

## Where secrets live

| Secret | Store | Notes |
|---|---|---|
| Server password / key text | OS keychain/keystore via `SecureStore` | prefs hold only `secure:srv_cred_<id>` markers |
| GitHub / GitLab tokens, AI key | `SecureStore` standalone keys | migrated from prefs once (`secrets_migrated_v1`) |
| SSH private key files | picked via file_picker, loaded via `SshKeyLoader` | key *material* never persisted except through `SecureStore` |
| Non-secret settings | SharedPreferences | safe for backup/export |

Rules: never print key material (`SshKeyLoader.describe` returns only the
non-secret fingerprint, e.g. "OPENSSH PRIVATE KEY, encrypted"); never put
raw credentials in the server-list JSON; run map entries through
`SecretHygiene.redactForLog` before logging.

## Audit (new)

`lib/services/secret_hygiene.dart` (pure Dart, tested) audits one decoded
server list without touching the store:

- `findRawCredentials` — ids whose credential is raw material (missed
  migration). Post-migration this must be empty; wire it into a debug /
  settings health row.
- `auditServers` — `{secure, raw, empty}` summary for that health row.
- `redactForLog` — masks password/token/secret/key-shaped entries.

If `findRawCredentials` is ever non-empty in production: re-run
`SecureStore.migrateIfNeeded()` (idempotent, best-effort), then rotate the
affected credentials — migration copies the secret, it does not expire it.

## Rotation + pruning (Alya's cutover)

`SecureStore.rotateServerCredential` / `pruneServerCredentials` (mandated
cutover branch) overwrite keychain entries without touching the masked
prefs JSON and delete entries for removed servers. Rotate on: suspected
exposure, team-member offboarding, and after any migration that copied a
previously-plaintext secret.

## CI / repo hygiene

- `security.yml` runs gitleaks on every PR to main — keep test fixtures
  free of real-looking secrets (this PR's tests use `hunter2`-grade dummies).
- Never commit `google-services.json`, `*.keystore`, `*.p12`, `.env` —
  `.gitignore` already excludes the standard names; check before adding
  platform integrations.
- Signing credentials (Play keystore, Apple certs) stay owner-held and
  manual — see `docs/release-process.md`. No CI secret wiring without a
  `need-owner-decision` sign-off.
