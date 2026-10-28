# Secrets-hardening runbook (toward flutter_secure_storage)

Decision context: `docs/decisions/001-credential-storage.md` mandates
Option A — full migration to `flutter_secure_storage` (Alya's cutover,
now merged to main; this runbook is the DevOps companion, not a second
implementation).

## Where secrets live

| Secret | Store | Notes |
|---|---|---|
| Server password / key text | OS keychain/keystore via `SecureStore` | prefs hold only `secure:srv_cred_<id>` markers |
| GitHub / GitLab tokens, AI key | `SecureStore` standalone keys | migrated from prefs once (`secrets_migrated_v1`) |
| Per-host agent token (v4 gate) | `SecureStore` key `agent_tok:<id>` | auto-provisioned by one-click install; Settings key icon to set/rotate/clear; wiped on server delete; never displayed |
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

## Rotation + pruning (in `SecureStore` on main)

`SecureStore.rotateServerCredential` / `pruneServerCredentials` overwrite keychain entries without touching the masked
prefs JSON and delete entries for removed servers. Rotate on: suspected
exposure, team-member offboarding, and after any migration that copied a
previously-plaintext secret.

## SSH host-key pinning (TOFU, in `SshHostKeys`)

Every `SSHClient` in the app (Settings test-connection + all seven
`AgentService` operations) passes `onVerifyHostKey` — dartssh2 accepts ANY
host key when that callback is null (MITM), and its own docs say so. Pins
are `SHA256:...` fingerprints (non-secret) in SharedPreferences under
`hostkey_<host>:<port>` as `{keyType: fingerprint}`.

- First connect to a host:port pins the key it sees (TOFU). The Settings
  test reports "New host key pinned" — verify that fingerprint out-of-band
  (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the server) before
  trusting it with real credentials.
- Same key type, different fingerprint later: connection REFUSED
  fail-closed ("possible MITM" in the UI). Check DNS/IP drift first.
- Legitimate reinstall / rotation: server dialog shows the pinned key with
  a FORGET button (per host:port). Forget, verify the new fingerprint
  out-of-band, reconnect to re-pin. Never forget-and-reconnect blindly on a
  mismatch you did not expect.
- Store I/O errors also fail closed (mismatch) rather than silently
  skipping verification.

## CI / repo hygiene

- `security.yml` runs gitleaks on every PR to main — keep test fixtures
  free of real-looking secrets (this PR's tests use `hunter2`-grade dummies).
- Never commit `google-services.json`, `*.keystore`, `*.p12`, `.env` —
  `.gitignore` already excludes the standard names; check before adding
  platform integrations.
- Signing credentials (Play keystore, Apple certs) stay owner-held and
  manual — see `docs/release-process.md`. No CI secret wiring without a
  `need-owner-decision` sign-off.
