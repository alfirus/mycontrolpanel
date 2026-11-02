# Privacy + permission disclosures — Play / App Store / Snap / Microsoft Store

Source of truth for every store questionnaire. All answers derive from code,
not intent: `android/app/src/main/AndroidManifest.xml`,
`ios/Runner/Info.plist`, `ios/Runner/AppDelegate.swift`, macOS
entitlements, `lib/services/background_alerts.dart`,
`lib/services/desktop_alerts.dart`, `lib/services/secure_store.dart`,
`docs/specs/tray-headless-privacy.md`, ADR-003
(`docs/decisions/003-tray-headless-security.md`). If code changes, update this
file in the same PR.

Review status: written by Ain (Tech Writer) from the files above;
Security review by Alya required before first submission (tag Alya as
reviewer on the release PR). Never answer a questionnaire from
memory: re-read the manifest/plist in the release PR and paste the
file paths into the review.

## What the app touches (all stores, same answers)

- Server IPs/hostnames, SSH usernames, credentials: stored in the OS
  keychain/keystore only (`flutter_secure_storage`), never transmitted
  anywhere except to the user's own servers over SSH (:22) and the user's
  own metrics agent (:9108, LAN). No first-party server, no account, no
  analytics, no crash reporting unless the user opts into Sentry (#26).
- AI provider keys: user-supplied, stored in the keychain, sent only to the
  provider the user configures (or local Ollama — stays on-device).
- GitHub/GitLab PATs: stored in the keychain, sent only to api.github.com /
  the user's GitLab host.
- Notifications: local only (`flutter_local_notifications` / `local_notifier`
  / WorkManager periodic ≥15 min; desktop in-app timer rail in beta.1).
  No FCM/APNs token, no push relay.
- Headless tick (Beta.2 tray plan — implemented behind
  `--poll-headless`, scheduler wiring pending): reads keychain
  in-memory only, writes no new persistent state beyond
  `background_alerts_last_check_ms` + last-seen set; scheduler argv
  carries no secrets (ADR-003, enforced by `HeadlessSecurity` +
  `test/headless_security_test.dart`).
- Background consent: single shared `background_alerts` pref,
  default OFF, binding copy "Polls your servers every ~15 min in the
  background." Consent OFF = no network, no vault touch (exit 2
  headless). A locked vault (biometrics ON) denies background reads.

## Google Play — Data safety (declare when listing)

- Collects: approximate location? NO. Personal info? NO. App activity
  (server IPs the user enters)? Stored on-device only — answer "collected"
  ONLY if Play counts user-entered infra data; default answer: no data
  shared with third parties, no data collected off-device.
- Permissions declared: `POST_NOTIFICATIONS` (runtime prompt on API 33+,
  requested when the background toggle flips on), `USE_BIOMETRIC`
  (app-lock only). Deliberately NOT declared:
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`,
  `RECEIVE_BOOT_COMPLETED` (WorkManager reschedules with its own
  merged receivers — no app declaration needed).
- Account deletion: n/a — no account exists.

## Apple App Store — privacy nutrition + purpose strings

- Data linked to user: none off-device. Answer "Data Not Collected" unless
  the user enables Sentry opt-in (then: crash data, linked, opt-in).
- `NSFaceIDUsageDescription`: biometric app lock (already in
  Info.plist: "Unlock My Control Panel with Face ID").
- Background modes: `fetch` + `BGTaskScheduler` periodic task only;
  identifier (`BackgroundAlerts.taskName` =
  `com.mycontrolpanel.my_control_panel.backgroundAlerts`) must equal
  the permitted identifier and the AppDelegate registration or iOS
  throws BGTaskSchedulerErrorDomain Code=3 at task launch.
- Local notifications need no plist entitlement — only the runtime
  notification prompt (requested in-app when the toggle flips on).

## Snap Store

- Confinement: strict preferred. Plugs to declare: `network` (SSH + agent
  LAN reads), `network-bind` only if the snap itself serves anything (it
  does not — omit unless the build proves otherwise). Home read only for
  SSH-key file-picker import.
- Daemons: none. Tray-mode systemd user timers (Beta.2) are per-user units
  installed by script, not snap daemons — state this in the listing notes.

## Microsoft Store

- Capabilities: private-network client/server (LAN agent reads), no admin,
  no elevation, per-user install. No background task declaration while
  tray mode ships as Task Scheduler scripts (Beta.2); declare a Windows
  background task ONLY if a UWP-component lands — it has not.

## Red lines (any store)

- Never add a permission to silence a store warning (e.g. battery exemption
  as a manifest permission) — fix the flow, not the manifest.
- Never claim tray-mode closed-app desktop alerts as shipped until
  the Beta.2 gate (Balqis matrix green + Burhanah asset verification)
  closes.
- Never answer a questionnaire from memory: re-read the manifest/plist in
  the release PR and paste the file paths into the review.
