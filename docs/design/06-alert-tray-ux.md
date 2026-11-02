# 06 — Alert UX + Tray-Mode Design Package (Kira)

Owner: Kira (UI/UX) · Status: build-ready spec · Implementer: Nurul (inbox),
Elizabeth (tray shell), Lisa (headless payload)
Scope: alert experience + tray-mode UX coherence for Beta.2 (`v1.0.0-beta.2`),
building on Rina's tray-mode plan (`docs/project/tray-mode-plan.md`, WBS TM-4/TM-5)
and the closed-app architecture (`05-background-alerting.md` §8).
Executable half: `lib/theme/alert_tokens.dart` + `test/alert_tokens_test.dart`.

Non-goals: remote push (FCM/APNs), exact-time guarantees, multi-window
management — all deferred per §8.5. No new payload formats: every rail goes
through `NotificationHook.build` verbatim.

## 1. Three-severity spec

| Severity | Meaning | Color token | Icon | Pill |
|---|---|---|---|---|
| `critical` | act now: failed unit, disk ≥90%, brute-force ≥20, OOM | `critical #EF4444` | `error` | CRITICAL |
| `warning` | look soon: disk ≥80%, brute-force ≥5, load > nproc, reboot <1h | `warning #EAB308` | `warning` | WARNING |
| `info` | recovery / FYI: alert cleared, back-to-normal | `info #06B6D4` | `info` | INFO |

Rules:
- Status meaning ⇒ `success/warning/critical/info` ONLY (spec 01). The
  `accent*` brand set never carries severity. `accentCyan` stays reserved for
  primary actions / live affordances, always paired with a second cue.
- Severity is computed once, upstream (`AlertRules`/`Thresholds`). The inbox,
  the tray icon, and the OS toast all read the same value — they never
  re-derive it with different cutoffs.
- Recovery is a first-class entry: when a firing alert clears, the inbox
  shows one `info` row ("Back to normal: …") instead of silently dropping
  the row. No recovery → users learn to distrust silence.

## 2. Copy tone (use verbatim — `AlertCopy`)

Headlines state WHAT is true (≤48 chars). Bodies state WHY + WHAT TO DO
(≤140 chars, exactly one action). No blame ("you failed to…"), no jokes at
`critical`, no silent fake data (spec 04 honest-data rule).

| Context | Headline | Body |
|---|---|---|
| critical toast | `MyControlPanel: action needed` | fresh titles (max 3 + "…and N more") |
| warning toast | `MyControlPanel: warning` | fresh titles (max 3 + "…and N more") |
| recovery toast | `MyControlPanel: back to normal` | cleared titles |
| inbox empty | `ALL CLEAR` | `No firing alerts across your servers. New warnings and failures land here.` |
| ack | (snack) | `Acknowledged — removed from the firing list.` |
| snooze | (snack) | `Snoozed for 1 hour — fires again if still down.` |

Title/body templates live in `AlertCopy.notificationTitle`; Nurul wires them
straight into `NotificationHook.build(title, freshTitles)` for inbox +
in-app display copy. Frozen-headless note: the TM-1 stdout payload title is
frozen as `'MyControlPanel alert'` (`docs/specs/headless-cli-contract.md`
§5) — Lisa does NOT change it. Per-severity titles above are the display
layer's copy (inbox rows, tray-helper toasts); the headless JSON keeps the
frozen title until Rina signs a contract change.

## 3. Tokens (`AppAlertTokens`, executable)

`lib/theme/alert_tokens.dart` freezes: per-severity `color/icon/pill/
semanticLabel`, per-tray-state `trayColor/traySemanticLabel`, action ids +
labels, `QuietHours`, `AlertGrouping`, `AlertSettingsOrder`, `AlertA11y`.
Contrast: every severity color ≥4.5:1 on `surface0` (AA normal text),
asserted in `test/alert_tokens_test.dart` — not eyeballed:
critical 5.3:1, warning 10.3:1, info ~7:1 (same ramp as spec 01 §2).

## 4. Grouping / dedup / exactly-once (TM-5)

1. **Identity**: `AlertWatch.keyFor` verbatim on every rail. The inbox and
   the headless tick share ONE last-seen set — never a second inbox-side set.
2. **Grouping is presentation only**: inbox groups fresh titles by server
   (`AlertGrouping.groupByHost`, `(host)` suffix; CI lines under "Other"),
   max 4 groups × 5 items + "…and N more" tail (`flattenForInbox`). The OS
   toast ignores groups and uses `NotificationHook.build` (max 3 + overflow)
   so the headless payload shape never changes.
3. **Exactly-once**: in-app timer + headless tick both diff against the
   shared set; one fresh batch ⇒ exactly one toast, never both. Balqis proves
   open + closed cases in the TM-6 matrix.
4. **Ordering**: critical first, then warning, then info; within a severity,
   newest first. Stale entries (older than 2 poll intervals without
   re-fire) sink below fresh ones with a `STALE` badge, never vanish silently.

## 5. Quiet hours (`QuietHours`)

- Default OFF. Default window 22:00–07:00 local, user-editable start/end.
  Overnight wrap supported; start == end means "never quiet", never "always".
- While quiet: no toasts on any rail; the tray icon switches to `quiet`
  (muted `textSecondary` dot + "Quiet until 07:00" tooltip); the inbox still
  collects. Critical does NOT punch through in Beta.2 (explicit non-goal —
  punching through is a consent + store-review question for Post-1.0).
- Quiet state is honest: Settings row shows the window label
  (`22:00 – 07:00` / `Off`); the staleness line keeps ticking
  ("last checked Xm ago") so quiet is never confused with broken.
- Pref keys (`alerts_quiet_hours_enabled/_start_minutes/_end_minutes`)
  declared in `QuietHours` so inbox + tray helper read the same keys.
  Enforcement is NOT headless: per the frozen TM-1 contract the headless
  tick always runs to completion (exit 0/2/1); quiet is enforced at the
  notify layer (tray helper suppresses toasts, icon shows `quiet`), so the
  inbox still collects every firing signal and `lastSentMs` 6 h flap
  suppression keeps working underneath.

## 6. Notification actions

Stable ids (Lisa/Elizabeth key deep-link payloads off these — never rename
without a migration note):

| Id | Label | Effect |
|---|---|---|
| `mcp.open` | Open | body tap + button 1: open app → inbox (mobile) / restore window (desktop) |
| `mcp.ack` | Ack | mark seen (shared set), dismiss |
| `mcp.snooze.1h` | Snooze 1h | suppress re-toast 1h, inbox keeps the row |
| `mcp.mute.till_morning` | Mute night | enable quiet-hours until 07:00, one tap |

Max 3 buttons + body tap on desktop; Android shows all 4 in expanded view.
Every action funnels through the shared seen-set so ack-on-one-rail clears
all rails. Payload: `{action, alert_keys[]}` — no secrets, ever (Alya ADR-003).

## 7. Tray-mode UX (TM-4)

### 7.1 Icon states

| State | Dot | Tooltip | When |
|---|---|---|---|
| `ok` | `success` green | `MyControlPanel — all clear` | last tick clean |
| `firing` | `critical` red | `MyControlPanel — N alerts firing` | any unacked critical/warning |
| `stale` | `warning` amber | `MyControlPanel — last checked Xm ago` | tick failed / backoff active |
| `quiet` | `textSecondary` grey | `MyControlPanel — quiet until HH:MM` | quiet-hours active |

Linux needs monochrome fallbacks (some trays strip color): pair every dot
with a shape overlay (✓ / ! / ? / ☾ as text glyph in the 16px canvas).
macOS menu-bar uses the template (silhouette) variant; Windows uses full
color. Never color-only — shape + tooltip + semantic label always.

### 7.2 Tray menu (order fixed)

1. Status header (read-only): `● 2 firing · last checked 3m ago`
2. `Open MyControlPanel`
3. `Mute until morning` / `Unmute` (toggle reflects quiet state)
4. `Check now` (one manual tick, rate-limited to 1/min)
5. `Settings…` (deep link to the Alerts section, §8)
6. `Quit`

Menu items ≥24px rows on desktop (OS chrome), full 48px targets inside the
app. Every menu item gets a screen-reader name = its visible label.

### 7.3 Onboarding (first-run, one screen, skippable)

Title `Stay notified when the app is closed` + body (`AlertCopy.
onboardingBody`) + primary `ENABLE BACKGROUND ALERTS` / secondary `NOT NOW`.
Rules: shown once, after the first server is added (no servers ⇒ nothing to
poll ⇒ never prompt); `NOT NOW` dismisses forever (re-entry via Settings);
enabling flips the shared `background_alerts` pref ON and fires the OS
permission prompt immediately after, so the two consents read as one decision.
Wireframe (ASCII, 360dp):

```
+----------------------------------+
|  (tray glyph: bell + check)      |
|  Stay notified when the          |
|  app is closed                   |
|                                  |
|  MyControlPanel can minimise to  |
|  the tray and check your servers |
|  every ~15 min in the background.|
|  You choose: toast for critical  |
|  only, or all severities — and  |
|  quiet hours pause everything.   |
|                                  |
|  [ ENABLE BACKGROUND ALERTS ]    |
|  [ NOT NOW ]                     |
+----------------------------------+
```

### 7.4 Closed-app affordances

- Minimise-to-tray (not quit) is the default close-box behavior on desktop
  once consent is ON, with a one-time explainer toast ("Minimised to tray —
  checks continue. Quit from the tray menu."). Consent OFF ⇒ close quits.
- Window-restore: tray `Open` / toast tap restores the existing window
  (single-instance lock — never a second window). Cold start from a toast
  lands on the inbox, scrolled to the tapped alert.
- Crash honesty: if the headless tick fails twice in a row, the tray flips
  to `stale` and the next `Open` shows a `SYNC FAILED / RETRY` StateView
  (spec 04) — never a green icon on a dead poller.

### 7.5 Permission-denied + opt-out states

- **Denied** (OS prompt refused): inbox banner `NOTIFICATIONS BLOCKED` +
  body (`AlertCopy.permissionDeniedBody`) + `OPEN OS SETTINGS` (deep link
  where the OS allows, else static guidance text). Alerts still collect in
  the inbox; the tray icon keeps working. Re-check permission on every
  Settings open — clear the banner the moment it is granted.
- **Opt-out** (shared toggle OFF): one confirmatory snack
  (`AlertCopy.optOutBody`); current tick finishes, no new ticks; tray menu
  shows `Background alerts off — enable in Settings`; in-app watcher keeps
  working while open. No guilt copy, no re-prompt.
- **Vault locked** (headless, biometric gate): tick exits 2, fail closed,
  no prompt from the background (ADR-003). Tray shows `stale` with tooltip
  `Unlock to resume checks`; next foreground unlock resumes silently.

## 8. Settings IA — Alerts section (final order)

Single source: `AlertSettingsOrder.rows`. One section, this order, no second
desktop pref:

1. `Background alerts` — shared consent toggle (existing
   `BackgroundAlertConsentTile`, default OFF, `consentCopy` + tray sentence).
2. `Severities` — segmented: `Critical only` (default) | `All`. Controls
   toasts only; inbox always collects everything.
3. `Quiet hours` — OFF default; start/end time pickers; summary label.
4. `Thresholds` — per-metric warn/crit (disk, brute-force; Nurul builds the
   editors on `AlertRules` defaults; headless reuses verbatim).
5. Platform explainer — Android battery tip / iOS scheduling tip (existing
   copy, shown only on that platform).
6. `Last checked …` — read-only staleness line (existing, always visible when
   ON; "Never" before the first tick).

## 9. Design-system / a11y pass (store readiness)

WCAG 2.2 AA, asserted where computable (`AlertA11y` + token tests):

1. **Names, not colors**: every severity pill, tray state, and state icon
   carries a `semanticLabel` (`Critical alert`, …). Zero color-only meaning
   anywhere on this surface.
2. **Contrast**: alert body copy ≥11px in `textSecondary` or brighter
   (5.8:1, AA) — never `textMuted` (2.6:1, fail) per spec 01. Severity colors
   ≥4.5:1 on `surface0` (test-pinned). Snapshot check before store submit.
3. **Targets**: 48×48 minimum on all in-app controls (ack/snooze chips,
   threshold steppers, quiet-hour pickers). Tray-menu rows follow OS chrome
   (≥24px) — acceptable per WCAG target-spacing exception, documented here.
4. **Live regions**: inbox loading + new-error arrivals announce
   (`Semantics(liveRegion: true)`, `loadingAnnouncement`/`errorAnnouncement`);
   badge-count changes announce the count, not the whole list.
5. **Reduced motion**: pulsing firing-dot and spinners respect
   `MediaQuery.disableAnimations` (static icon + text, per spec 04 §3.5).
6. **Focus order**: inbox list → filters → detail sheet → settings link;
   visible focus ring (cyan 2px outline) on every focusable; Esc closes the
   detail sheet and returns focus to its row.
7. **Text scaling**: layout holds to 200% system text (overflow → wrap, never
   clip; toast bodies already cap at 3 lines + overflow note).

## 10. Handoff to Nurul (inbox) / Elizabeth (tray) / Lisa (headless)

- **Nurul** (`t_7ba899fe`): build on `alert_tokens.dart` — `AppAlertTokens`
  for pills/icons, `AlertCopy` verbatim, `AlertGrouping` for the list,
  `AlertSettingsOrder.rows` for the section, `AlertA11y` for the test bar.
  Filter chips (All/Unread/Critical), swipe ack/snooze, detail sheet with
  metric snapshot + stale badge + open-host, notification-tap deep links
  (`mcp.open` payload).
- **Elizabeth** (tray shell, TM-3): icon states §7.1, menu order §7.2,
  restore/single-instance §7.4, denied/opt-out §7.5.
- **Lisa** (headless, TM-1): action ids §6, quiet-hours keys §5 (notify-layer
  only — headless honors the frozen contract verbatim), shared
  seen-set §4. Headless never invents copy — titles from
  `NotificationHook.build`, window chrome from this doc.
- **Balqis** (TM-6): matrix rows — open+closed × consent on/off × quiet
  on/off × denied × vault-locked; exactly-once assertion per §4.3.

## 11. Definition of done (this card)

- [x] This doc + `alert_tokens.dart` + `alert_tokens_test.dart` on main.
- [x] `flutter analyze` clean, `flutter test` green (incl. new tests).
- [x] No payload/threshold/policy changes — reuse verbatim (reviewer: grep
      `NotificationHook.build`, `AlertRules`, `PollPolicy` — zero new forks).
- [ ] Kira sign-off recorded on Nurul's inbox PR (follow-up, not this card).
