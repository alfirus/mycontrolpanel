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
- Staleness stamp is shared with mobile: every in-app fan-out tick calls
  `DesktopAlerts.recordCheck()` → the same `background_alerts_last_check_ms`
  pref, so the alerts-surface "last checked …" line (`AlertsStalenessLine`,
  copy via `BackgroundAlerts.lastCheckedLabel`) stays honest on desktop
  while the app runs.

## 8. Closed-app architecture — tray mode (Beta.2, `v1.0.0-beta.2`)

Program plan: `docs/project/tray-mode-plan.md` (WBS TM-1…TM-8, RACI,
critical path). Decision owner for this section's contract: Lina
(headless-CLI architecture, binding); Zara implements scheduler wiring;
Alya reviews scheduler security; Kira designs tray UX.

### 8.1 Shape: one headless poll, three schedulers, one tray shell

- **Headless poll CLI (TM-1).** A single entry-point, e.g.
  `mycontrolpanel --poll-headless`, that runs one poll tick with no
  window: read servers + thresholds from the existing store, reuse
  `PollPolicy`/`Thresholds` verbatim, diff against the shared last-seen
  set, and emit `NotificationHook.build` output (`{title, body}`, max 3 +
  "…and N more") into the OS notification rail. Suggested contract
  (Lina to freeze by 2026-11-21): exit `0` = tick ok (alerts or not),
  `2` = tick skipped (consent OFF / no network / backoff active), `1` =
  error; stdout is machine-readable JSON of the built notification or
  empty; never prints secrets.
- **OS schedulers (TM-2/TM-3).** Windows Task Scheduler (logon + repeat
  trigger, per-user task, no elevation) and Linux systemd user timer
  (same CLI — one design covers both, as §2 anticipated) invoke the
  headless CLI at the user's `refresh_interval`, floored at ~15 min.
  macOS gets a menu-bar/tray helper instead of a bare LaunchAgent: the
  helper owns the icon + menu and invokes the same headless tick.
- **Tray shell (TM-4).** Icon states (ok / firing / stale), menu
  (Open / mute-until / Quit), deep link into Settings consent row. The
  tray shell never polls by itself — it surfaces headless-tick results.

### 8.2 Invariants (carried over from beta.1, non-negotiable)

- Same payload end to end: `NotificationHook.build` verbatim on every
  rail — snack bar today, OS toast tomorrow, headless tick next.
- Same consent: the shared `background_alerts` pref (default OFF) gates
  the headless path; no second desktop pref.
- Same honesty: every headless tick calls `DesktopAlerts.recordCheck()`
  → `background_alerts_last_check_ms`, so "last checked Xm ago" stays
  true with the window closed.
- Exactly-once across rails: in-app timer and headless tick share one
  last-seen set — exactly one toast per fresh batch, never both (TM-5
  gate, TM-6 proof for open + closed cases).
- Vault-only credentials: the headless process reads secrets from the OS
  vault; scheduler args carry no token, key path, or passphrase (Alya
  review, TM-2).

### 8.4 Security boundary — ADR-003 (binding on TM-1/TM-2/TM-3)

Alya's review is frozen in `docs/decisions/003-tray-headless-security.md`
(STRIDE table T1–T8) + privacy companion
`docs/specs/tray-headless-privacy.md`. Lina builds to it, Zara wires
schedulers inside it, Balqis proves it in TM-6. Non-negotiables:

- Read-only biometric-gated vault; locked vault denies background reads
  (fail closed, exit 2, no headless prompt).
- No plaintext fallback: non-`secure:` markers never reach the poller.
- OS-ACL-scoped storage (per-user paths only, mode 0600 where files).
- Least-privilege scheduler artifacts: per-user, no elevation, argv
  carries no token/key path/passphrase (`HeadlessSecurity` enforces +
  tests `test/headless_security_test.dart`: locked-vault-denies,
  tampered-artifact).
- Consent honored headless: shared `background_alerts` pref (default
  OFF) gates every tick. Privacy: on-device only, no new retained state
  beyond the existing last-check stamp + last-seen set.

### 8.5 What stays out (Beta.2 non-goals)

- Remote push (FCM/APNs relay) — still local notifications only.
- Exact-time guarantees — schedulers are best-effort; staleness copy
  absorbs drift.
- Multi-window management beyond the tray shell; Android
  background-service limits stay Post-1.0.
