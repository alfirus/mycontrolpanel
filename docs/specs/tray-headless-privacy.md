# Tray headless polling — privacy note (companion to ADR-003)

Scope: the Beta.2 headless tick (`--poll-headless`) and its OS scheduler
artifacts. Binding alongside `docs/decisions/003-tray-headless-security.md`.

## Data minimization

- The headless tick reads only what a poll needs: server host/port/username
  (prefs, non-secret) + credentials (OS vault, in-memory only, never
  persisted headless). No contacts, location, files, or telemetry.
- Poll results stay on-device: firing titles render into the local OS
  notification rail via `NotificationHook.build`. No relay, no FCM/APNs,
  no analytics egress (same as beta.1 mobile/desktop rails).
- Scheduler argv, stdout JSON, and logs carry **no secret material** —
  enforced by `HeadlessSecurity.findSecretMaterialInArgs` and
  `SecretHygiene.redactForLog`.

## Consent

- Single opt-in: the shared `background_alerts` pref, default OFF, with the
  binding copy "Polls your servers every ~15 min in the background."
- Consent OFF headless = do nothing (exit 2, no network, no vault touch).
  Turning the toggle off also stops future scheduler ticks from polling —
  Zara's uninstall/disable path removes or disables the artifact.
- Enabling the app lock (biometrics / device PIN) additionally denies
  background credential reads: a locked vault skips the tick rather than
  prompting headless.

## Retention

- Headless tick keeps no new persistent state beyond the existing shared
  stamps: `background_alerts_last_check_ms` (staleness honesty) and the
  shared last-seen alert set (exactly-once rail dedupe). Both already exist
  in beta.1 and hold no secrets.
- Uninstall removes the per-user scheduler artifact; server delete /
  clear-all already purges keychain entries (`SecureStore`).

## User controls (Settings)

1. Background-alerts toggle (consent, default OFF).
2. Biometrics toggle (vault gate for background reads).
3. Server delete / clear-all (keychain purge).
4. OS-level controls remain authoritative: notification permission,
   battery-optimisation exemption (Android, manual), Task Scheduler /
   systemd / LaunchAgent disable.
