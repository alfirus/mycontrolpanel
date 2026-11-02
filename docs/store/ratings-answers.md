# Store ratings + questionnaire answers — MyControlPanel

Source of truth for every store questionnaire. All answers derive from
code, not intent: Android manifest, iOS Info.plist, macOS entitlements,
`docs/specs/tray-headless-privacy.md`, ADR-003, and
`docs/store/privacy-permissions.md`. If code changes, update this file in
the same PR. Never answer a questionnaire from memory.

## Shared content profile (all stores)

- App type: server-monitoring utility. No user-generated content, no
  user-to-user communication, no social feed, no chat with strangers.
- No gambling, no contests with prizes, no ads, no in-app purchases
  (MIT Community edition, RM 0).
- No sexual, violent, or hateful content. No medical, legal, or financial
  advice. AI assistant answers are grounded in the user's own fleet data.
- No location tracking. No cross-app tracking for advertising.
- Minimum audience: IT operators. No child-directed content, but nothing
  unsuitable for general audiences either.

## Google Play — content rating + data safety

Content rating questionnaire (IARC):

- Violence: none. Sexual content: none. Language: none (terminal shows the
  user's own server output; no profanity filter claims).
- User interaction: none — no user-generated sharing, no messaging.
- Gambling: none. Expected rating: Everyone.
- Ads declaration: NO ads.
- Target age: 18+ operators in practice, but no age gate required beyond
  the Everyone rating.

Data safety (declare when listing):

- Data collected off-device: none by default. Server IPs the user enters
  stay on-device (keychain + app storage); answer "collected" ONLY if Play
  counts user-entered infra data — default answer: no data shared with
  third parties, no data collected off-device.
- Exception path: if the user enables the Sentry opt-in, declare crash
  data (linked, opt-in, user-controlled).
- Permissions declared: `POST_NOTIFICATIONS` (runtime prompt on API 33+,
  requested when the background toggle flips on), `USE_BIOMETRIC`
  (app-lock only). Deliberately NOT declared:
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `RECEIVE_BOOT_COMPLETED`.
- Account deletion: n/a — no account exists.

## Apple App Store — age rating + privacy nutrition

Age rating questionnaire:

- No objectionable content in any category (violence, sexual content,
  profanity, gambling, horror, medical, controlled substances: all NONE).
- No user-generated content, no web browsing to unrated sites, no
  messaging. Expected rating: 4+.
- `NSFaceIDUsageDescription`: biometric app lock (already in Info.plist).
- Background modes: `BGTaskScheduler` periodic task only; the task
  identifier must equal the permitted identifier and the AppDelegate
  registration or iOS throws at launch of the task.

Privacy nutrition:

- Default answer: Data Not Collected (no off-device collection, no
  tracking).
- Sentry opt-in path: if enabled by the user, declare crash data, linked
  to the user, used for app functionality, opt-in only.
- AI provider keys: sent only to the provider the user configures (or stay
  on-device with local Ollama) — declare under the provider's own policy,
  not ours.

## Microsoft Store — age rating

- Questionnaire: no violence, no sexual content, no gambling, no
  user-generated sharing. Expected rating: EVERYONE (ESRB) / PEGI 3.
- Capabilities: private-network client (LAN agent reads), no admin, no
  elevation, per-user install.
- No background task declaration while tray mode ships as Task Scheduler
  scripts (Beta.2); declare a Windows background task ONLY if a UWP
  component lands — it has not.

## Snap Store

- No age-rating questionnaire. Keep the confinement note in the listing
  (`docs/store/listings-matrix.md` §3c): strict, `network` plug, no
  daemons, tray scheduling via per-user systemd units installed by script.

## Red lines (any store)

- Never add a permission to silence a store warning (e.g. a battery
  exemption as a manifest permission) — fix the flow, not the manifest.
- Never answer a questionnaire from memory: re-read the manifest / plist
  in the release PR and paste the file paths into the review.
- Never promise push notifications, real-time streaming, or background
  polling as built — the tray-mode program (Beta.2,
  `docs/project/tray-mode-plan.md`) is the delivery vehicle, not a shipped
  feature.
- Never list on Snap / Microsoft until the package builds from CI
  (Beta.2 TM-2/TM-8 scope).

## Handoff

Messaging questions → Naura (CMO). Manifest / plist / entitlement truth →
via Sofia to Maisarah's team. Release verification → Burhanah.
