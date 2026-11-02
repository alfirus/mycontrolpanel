# ADR-003: Tray-mode headless credential boundary + scheduler hardening

Status: **accepted** — Alya (security), 2026-11-02. Binding on TM-1/TM-2/TM-3.
Lina builds the headless CLI to this ADR; Zara wires schedulers inside it;
Balqis proves it in the TM-6 matrix.

Context: `docs/design/05-background-alerting.md` §8 (tray mode) introduces a
headless poll CLI plus three OS schedulers. Beta.1 (ADR-001 vault-only
credentials, owner ruling 2026-10-28) assumed an interactive session: the
user unlocks the app, the keychain is available, healing can run. The
headless tick runs with **no window, no biometric prompt, no user to answer
questions** — so the credential boundary and the scheduler artifacts need
explicit hardening. This ADR freezes that boundary.

## Decision

One headless poll tick, six non-negotiable guardrails (enforced in
`lib/services/headless_security.dart`, proven in
`test/headless_security_test.dart`):

1. **Read-only, biometric-gated vault.** The headless tick only *reads*
   `secure:` entries. It never writes, migrates, or heals secrets — healing
   stays in the interactive session (`SecureStore.readServers`). When the
   app lock (`lib/services/app_lock.dart`) is engaged, the OS vault is
   treated as locked and background reads are denied (fail closed, exit 2).
2. **No plaintext fallback.** `resolveCredential` returns null for any
   marker that is not `secure:…` — legacy raw prefs material never reaches
   the headless poller, even if the keychain read would succeed.
3. **OS-ACL-scoped storage.** Prefs + scheduler artifacts live in per-user
   locations only: `%LOCALAPPDATA%` / task path `\MyControlPanel\`
   (Windows), `~/.config/systemd/user/` mode 0600 (Linux), per-user
   `~/Library/LaunchAgents/` mode 0600 (macOS). No system-wide tasks,
   daemons, or world-readable credential-adjacent files.
4. **Locked-vault denies background reads.** Null/empty vault secret →
   skip the host, exit 2, no hot retry, no headless biometric prompt.
5. **Least-privilege scheduler artifacts.** Per-user scope, no elevation
   (no highest-privileges / root / sudo), argv carries no token, key name,
   key path, or passphrase. `validateSchedulerArtifact` rejects violations;
   Balqis re-runs it in the TM-6 matrix (tampered-artifact case).
6. **Consent honored headless.** The shared `background_alerts` pref
   (default OFF) gates every headless tick — no second desktop pref. Consent
   OFF → exit 2, touch nothing, notify nothing.

Exit codes (TM-1 contract): `0` = tick ok, `2` = skipped (consent OFF /
vault locked / backoff), `1` = error. Stdout is machine-readable JSON of
the `NotificationHook.build` payload or empty; **never prints secrets**
(`SecretHygiene.redactForLog` at the logging choke point).

## STRIDE threat model — headless tick + schedulers

| # | Category | Threat | Mitigation (this ADR) | Residual / owner |
|---|---|---|---|---|
| T1 | Spoofing | Rogue scheduler task invokes the CLI with attacker args to exfiltrate or poll a hostile host | `validateSchedulerArtifact`: per-user scope, exact `--poll-headless` entry-point, argv secret scan; TM-6 tampered-artifact test | Low — Zara installs via signed scripts only |
| T2 | Tampering | Attacker edits the systemd unit / task XML to add `--token=` or widen scope | Same validation at install + TM-6 re-check; artifacts in per-user, mode-0600 paths | Low — file-integrity spot-check in TM-6 |
| T3 | Repudiation | Silent headless failure (missed firing alert) with no trace | Every tick writes `background_alerts_last_check_ms`; exit codes + JSON stdout logged secret-free | Low — staleness UI makes gaps visible |
| T4 | Information disclosure | Token/key path/passphrase leaks via scheduler argv, process list, or logs | Vault-only reads inside the process, never argv/env; stdout/log redaction; `findSecretMaterialInArgs` CI gate | Low — gitleaks + argv scan in CI/TM-6 |
| T5 | Information disclosure | Locked-device vault read by background tick (stolen laptop polls servers) | Locked-vault denies: app-lock-engaged → exit 2, no read attempted | Low — depends on user enabling app lock; documented in privacy spec |
| T6 | Denial of service | Headless tick hot-loops SSH on failure, draining battery / getting IP blocked | Reuse `PollPolicy` backoff verbatim (base 5 min → cap 1 h); skip-don't-retry on vault-lock | Low |
| T7 | Elevation of privilege | Scheduler task installed system-wide or with highest privileges | Per-user + no-elevation validation; install scripts never request elevation; review gate (Alya on TM-2) | Low — Alya review is a Beta.2 exit item |
| T8 | Spoofing | Plaintext prefs credential picked up headless after a failed migration | No-plaintext-fallback: non-`secure:` marker resolves to null (host skipped, re-entry forced in UI) | Low — `SecurityPosture` critical finding stays visible |

## Scheduler hardening reference (Zara implements, Alya reviews)

Windows Task Scheduler: per-user task (`\MyControlPanel\poll-headless`),
logon + repeat trigger (~15 min floor), *no* "run with highest privileges",
*no* stored password on the principal, action argv exactly
`mycontrolpanel.exe --poll-headless`. Linux systemd user timer:
`~/.config/systemd/user/mcp-poll.timer` (`OnUnitActiveSec=15min`,
`AccuracySec=1min`) + `.service` with `ExecStart=… --poll-headless` and
**no** `Environment=` secrets. macOS: per-user LaunchAgent plist
(`~/Library/LaunchAgents/`, `StartInterval` 900) invoking the same flag;
no LaunchDaemon. Full snippets live in the TM-2 runbook (Ain); the
invariants above are what Alya signs off.

## Consequences

- Lina's TM-1 contract gains exactly one security section: this ADR. No
  new prefs, no new payload formats, no FCM/APNs.
- A headless tick on a locked-vault or opted-out machine does nothing by
  design — Balqis must test the *skip* paths, not just the toast path.
- Privacy companion: `docs/specs/tray-headless-privacy.md`.
