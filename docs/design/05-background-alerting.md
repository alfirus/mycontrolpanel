# Background alerting + push — per-platform design (beta.1)

Closes #20 (design half). Foreground verification status first, then the
closed-app design. Owner call needed only on plugin/store-review cost
(see §6) — everything else is team's discretion.

## 1. Foreground watcher — verified

- `AlertWatch` diffs firing alerts + failed CI runs on every auto-refresh
  while the app is open: bell badge + snack of `freshTitles` (max 3).
- No busy-loop SSH: `_startAutoRefresh` ticks every 5 s but re-polls only
  when the user's `refresh_interval` (default 15 s) has elapsed, and only
  when Settings → auto_refresh is on. Each collector is guarded internally;
  consecutive background-policy failures back off exponentially
  (`PollPolicy`: base 5 min → cap 1 h).
- Battery/network: polls are short-lived TCP/SSH bursts on the existing
  session (no keep-alive); failure streaks back off instead of retrying hot.
  No behavior change needed for v1.
- Proof against real shapes: `test/release_gate_proof_test.dart` pins the
  trigger table (disk 79/80/90%, failed units incl. blanks skipped,
  brute-force 4/5/20, load vs nproc, OOM/kernel, reboot < 1 h,
  plaintext-credential flag, agent port 9108). These are the exact signals
  the watcher diffs — a firing signal on a real host flows through the
  same code path the tests pin.

## 2. Closed-app design (beta.1, `v1.0.0-beta.1`)

Same payload shape end to end: `NotificationHook.build` (`{title, body}`,
max 3 + "…and N more") already decouples producers from consumers — the
snack bar today, the OS notification tomorrow. Poll policy already exists
and is tested (`PollPolicy`, `Thresholds`, `Slo` in
`lib/services/polling_alerts.dart`). What remains is the per-platform
wake-up + notify plumbing:

| Platform | Wake mechanism | Notify | Constraints / notes |
|---|---|---|---|
| Android | `workmanager` periodic task (≥ 15 min OS minimum) | `flutter_local_notifications` | Doze batches alarms; exempt via "ignore battery optimisations" prompt for < 15 min freshness. Background-service limits: use WorkManager, not a foreground service, unless the user opts into persistent mode. |
| iOS | BGAppRefreshTask (system-scheduled, ~15 min–hours, not guaranteed) | `flutter_local_notifications` (local only, no APNs needed) | No exact timing; design for stale-tolerant state ("last checked Xm ago"). Background SSH from the sandbox works but keep sessions short-lived; store creds in Keychain (already the case). |
| macOS | `workmanager` does NOT support macOS — use a `Timer`-based poll while running + `flutter_local_notifications`; true closed-app push needs a LaunchAgent helper outside Flutter (out of scope for beta.1 — document as menu-bar/tray mode instead) | local notifications | Sandbox: network.client already entitled; notifications need user allow on first fire. |
| Windows | Same as macOS: in-app timer while running; closed-app delivery via Task Scheduler invoking a headless poll (future, needs a CLI entry-point — out of scope for beta.1) | local notifications (win_toast via the plugin) | No store review; cheapest platform to ship first. |
| Linux | In-app timer while running; closed-app via systemd user timer + headless poll (same CLI entry-point as Windows — one design covers both) | `flutter_local_notifications` (Linux impl uses notify-send path) | `libsecret-1-dev` already required for the vault; no new system deps. |

## 3. Recommended beta.1 slice (smallest shippable)

1. Add `flutter_local_notifications` + `workmanager` (mobile) behind the
   existing alert-polling Settings toggle — default OFF, explicit consent
   copy ("polls your servers every ~15 min in the background").
2. Wire `NotificationHook.build` output into the local-notification show
   call; reuse `PollPolicy`/`Thresholds` verbatim.
3. Desktop (macOS/Windows/Linux): in-app timer path only; document
   closed-app as tray-mode future work, not beta.1.
4. Tests: `NotificationHook` overflow/truncation (pure Dart, no plugin);
   widget test for the consent toggle; no OS-level scheduling in tests.

## 4. What stays out (explicit non-goals)

- Remote push (FCM/APNs server round-trip): local notifications suffice —
  the poll runs on-device against the user's own servers; no relay
  infrastructure to operate.
- Exact-time guarantees on mobile OSes: the card always shows
  "last checked …" so stale state is honest, never silent.
- New payload formats: `freshTitles` shape is frozen by this doc.

## 5. README linkage

- v1-ship Done list keeps the checked foreground-watcher line (verified
  per §1).
- v2-next "Background alert polling + push" stays unchecked and now points
  here — it is designed, not shipped.

## 6. Owner decision — RULED 2026-10-30 (binding, implemented in beta.1)

Background plugins GREEN-LIT for ALL platforms. Constraints:

- Default stays OFF with explicit consent copy: "Polls your servers every
  ~15 min in the background." (`BackgroundAlerts.consentCopy`,
  `background_alerts` pref, default false).
- Desktop headless closed-app (Task Scheduler / systemd user-timer CLI
  entry-point) DEFERRED to tray-mode work — desktop keeps the in-app timer
  path only (§3 item 3 unchanged).
- Shipped mobile slice: `flutter_local_notifications` +
  `workmanager` periodic task (`BackgroundAlerts.uniqueName`, ≥15 min OS
  minimum, `NetworkType.connected`, exponential backoff); iOS via
  BGTaskScheduler periodic task (`BackgroundAlerts.taskName` ==
  `BGTaskSchedulerPermittedIdentifiers` == AppDelegate
  `registerPeriodicTask` hint) + `registerLaunchHandlers()` (UIScene app);
  Android battery-optimisation via one-shot in-app guidance — the app
  deliberately does NOT declare `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
  (unused special permission = store-review red flag) and needs no
  `RECEIVE_BOOT_COMPLETED` (WorkManager reschedules with its own merged
  receivers). Only `POST_NOTIFICATIONS` is declared.
- No new payload formats: every notification goes through
  `NotificationHook.build` verbatim (foreground `AlertNotifications`,
  mobile `BackgroundAlerts.showFresh`, background tick). No FCM/APNs
  remote push. Stale-tolerant "last checked Xm ago" UI in Settings
  (`formatLastChecked` / `lastCheckedLabel`).

## 7. Desktop beta.1 slice — SHIPPED (in-app timer only)

Implemented in `DesktopAlerts` (`lib/services/desktop_alerts.dart`), driven
by the existing in-app timer while the app runs (control-center fan-out):

- `NotificationHook.build` output → `flutter_local_notifications` show
  calls on Windows (win_toast path via `AppUserModelId` + stable GUID),
  Linux (notify-send path via `defaultActionName`) and macOS (Darwin
  settings; user-allow prompt on first fire).
- Same consent toggle + default OFF as mobile: the shared
  `background_alerts` pref / `BackgroundAlertConsentTile` row — no second
  desktop pref. When consent is ON the desktop toast goes through this
  rail; otherwise the legacy `local_notifier` foreground rail
  (`AlertNotifications`, `notifications` pref) remains — exactly one
  desktop toast per fresh batch, never both.
- Reuses `PollPolicy`/`Thresholds` verbatim; no new payload formats.
- Closed-app delivery (Windows Task Scheduler / systemd user timer /
  macOS LaunchAgent headless CLI entry-point) is DEFERRED to tray-mode
  work — no scheduler wiring in beta.1; the single stub entry-point note
  is `DesktopAlerts.closedAppNote`. macOS closed-app specifically needs a
  menu-bar/tray helper outside Flutter (no LaunchAgent helper in beta.1).
