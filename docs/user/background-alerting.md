# Background alerting — user guide

Status: beta.1 shipped on main (`background_alerts` opt-in + desktop
in-app rail). Closed-app tray delivery (Windows Task Scheduler /
systemd user timer / macOS helper via `--poll-headless`) is
Beta.2-planned per `docs/project/tray-mode-plan.md` — not available
yet. This guide marks planned items PLAN explicitly; everything else
describes shipped behavior with code pointers.

## What it does

When your servers fire a signal (failed service, full disk, brute-force
SSH logins, overload, kernel errors — see the trigger table below),
MyControlPanel tells you without you staring at the dashboard:

- App open: bell badge + snack bar naming the fresh signals (max 3 +
  "…and N more").
- App closed, mobile: a local notification on your phone (no push
  relay, no server in the middle — the poll runs on-device against
  your own servers).
- App open, desktop (Windows/Linux/macOS): a local OS toast via the
  same path. Desktop closed-app delivery arrives with tray mode
  (Beta.2, PLAN).

What it never does: remote push (no FCM/APNs), exact-time guarantees,
or new alert kinds behind your back. Every rail renders the same
payload built by `NotificationHook.build` (`lib/services/polling_alerts.dart`).

## Turning it on (consent)

1. Open Settings → **Background alerts**.
2. Read the line under the toggle: "Polls your servers every ~15 min
   in the background." (`BackgroundAlerts.consentCopy`,
   `lib/services/background_alerts.dart`).
3. Flip it ON (default is **OFF**). Your OS asks for notification
   permission at that point — allow it, or there will be nothing to
   show to.
4. Leave it OFF and nothing polls in the background: no network, no
   vault touch, no notifications. Turning it back OFF later stops
   future ticks. (Code: `BackgroundAlerts.runBackgroundTick` returns
   immediately when the pref is OFF.)

One toggle covers mobile and desktop — there is no second
desktop-only switch (`DesktopAlerts.isEnabled` reads the same
`background_alerts` pref, `lib/services/desktop_alerts.dart`).

App-lock interplay: if you enable the biometric / device-PIN app lock,
a locked vault denies background credential reads — the tick skips
instead of prompting you headlessly (fail closed, ADR-003).

## Cadence — how often checks run

| Situation | Cadence | Source |
|---|---|---|
| App open (foreground watcher) | Ticks every 5 s; re-polls each server once your `refresh_interval` (Settings, default 15 s) has elapsed, and only while Settings → auto-refresh is ON (default ON) | `control_center_screen.dart` `_startAutoRefresh` |
| App closed, Android | WorkManager periodic task, **≥ 15 min OS minimum** — Android clamps anything lower | `BackgroundAlerts.pollFrequency`, `uniqueName: mcp-background-alerts-periodic` |
| App closed, iPhone | BGTaskScheduler periodic task; iOS treats ~15 min as a **hint** and may run it hours apart | `BackgroundAlerts.taskName`, `iosPromptBody` |
| App open, desktop | Same in-app timer as the foreground watcher; every tick records the shared last-check stamp | `DesktopAlerts.recordCheck` |
| Repeated failures | Back off exponentially: base 5 min doubling to a 1 h cap (`PollPolicy`: base 5 min → cap 1 h) | `lib/services/polling_alerts.dart` |
| Repeat of the same alert | Re-notified at most every **6 h** (resend cooldown); a resolved-then-firing signal notifies again | `HeadlessCheck.resendCooldown`, `AlertPollJob.notifyCooldown` parity |

Background ticks are cheap by design: short-lived polls on your
existing connection (no keep-alive), one sick host never sinks the
run, and each background tick covers at most your first 10 servers
with a 15 s per-host cap (`runBackgroundTick`).

## Battery and OS limits (per platform)

| Platform | What to expect | What to do |
|---|---|---|
| Android | The system batches background work (Doze) to save power; checks may slip past ~15 min. The app deliberately does **not** exempt itself — it never declares `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (a store-review red flag). | One-shot in-app guidance: Settings → Apps → MyControlPanel → Battery → **Unrestricted**. Manual, your choice (`batteryPromptBody`). |
| iOS | Apple decides when background checks run (~15 min at best, sometimes hours). Keep expectations on the staleness line, not the clock. | Keep **Background App Refresh** ON for MyControlPanel (`iosPromptBody`). |
| Windows / Linux / macOS (today) | No closed-app polling: toasts only while the app runs. macOS asks notification allow on first fire; Windows toasts need the registered app identity (handled by the app); Linux follows your notify-send path. | Keep the app running (minimised is fine). Closed-app delivery = tray mode, Beta.2 (PLAN). |

Declared permissions, nothing more: Android `POST_NOTIFICATIONS`
(runtime prompt on API 33+) + `USE_BIOMETRIC` (app lock only);
iOS `fetch` background mode + the single background-task identifier
`com.mycontrolpanel.my_control_panel.backgroundAlerts` (must match
the native registration or iOS refuses the task). No boot-receiver,
no battery-exemption permission — WorkManager reschedules with its
own receivers.

## The staleness line — "last checked …"

Because background timing is best-effort, the app never pretends to
be fresher than it is. Settings and the alerts surface show one of
(`BackgroundAlerts.formatLastChecked`):

- `Background alerts idle — never checked yet` (no tick has run)
- `last checked just now` (under 60 s)
- `last checked N min ago` / `last checked N hr ago` / `last checked N day(s) ago`

The stamp is written on **every** tick — even ones where every host
fails — so silence reads as stale, never as fresh (`recordCheck`,
`prefLastCheckKey: background_alerts_last_check_ms`). If the line
says hours, the data is hours old: open the app to force a poll.

## What triggers an alert

Same thresholds on every rail (`AlertRules`, `lib/services/alert_rules.dart`):

| Signal | Warns at | Critical at |
|---|---|---|
| Disk usage per mount | ≥ 80% full | ≥ 90% full |
| Failed systemd units | — | any unit |
| Failed SSH logins, trailing 24 h | ≥ 5 | ≥ 20 (possible brute force) |
| Load average vs CPU count | load1 > nproc (high) | load1 > 2 × nproc (overloaded) |
| Kernel lines, trailing 24 h | any lines (warning) | OOM-killer fired (critical) |

Exactly-once across rails: the foreground snack and the background /
desktop toast share one last-seen set, so one fresh batch produces
exactly one notification, never both (`AlertWatch` + `NotificationHook.build`).

## Troubleshooting

- **Toggled ON but no notifications:** check the OS notification
  permission (Android 13+ / iOS / macOS all gate on first prompt);
  check the staleness line — if it advances, polls run and there is
  simply nothing fresh.
- **Android checks hours apart:** battery optimisation is re-asserting
  itself — re-apply the Unrestricted step above after major OS updates.
- **iPhone checks hours apart:** normal iOS scheduling, not a bug —
  the staleness line is the honest clock.
- **Desktop toast never appears with the app closed:** expected in
  beta.1 — closed-app desktop delivery ships with tray mode (Beta.2).
- **Turned OFF but got one last toast:** a tick already in flight may
  finish; no new ticks start after OFF.

## Privacy in one paragraph

On-device only. Server addresses + credentials live in the OS
keychain/keystore and travel only to your own servers over SSH
(`:22`) and your own metrics agent (`:9108`, LAN). Poll results
render into the local notification rail — no relay, no push tokens,
no analytics egress. The background tick keeps no new state beyond
the last-check stamp and the last-seen set (both hold no secrets);
scheduler arguments never carry secrets (enforced in code,
`HeadlessSecurity`). Full text: `docs/specs/tray-headless-privacy.md`
+ ADR-003.

## Traceability (for reviewers)

Every claim above resolves to shipped code: `lib/services/background_alerts.dart`
(consent copy, ≥15 min, battery/iOS prompts, `formatLastChecked`,
`runBackgroundTick`), `lib/services/desktop_alerts.dart`
(shared pref, in-app-only, `closedAppNote`), `lib/services/polling_alerts.dart`
(`PollPolicy` 5 min→1 h, `NotificationHook` max 3),
`lib/services/alert_rules.dart` (thresholds), `lib/headless.dart` +
`lib/background/headless_check.dart` (Beta.2 contract: exit 0/2/1,
6 h cooldown — implemented behind `--poll-headless`, scheduler
wiring pending Zara/TM-2), `android/app/src/main/AndroidManifest.xml`
(permissions), `ios/Runner/Info.plist` (background identifier).
Planned-only items are labelled PLAN and covered by
`docs/project/tray-mode-plan.md` (Rina) and
`docs/design/05-background-alerting.md` §8 (Lina contract owner).
