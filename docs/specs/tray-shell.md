# Tray shell behavior spec (Elizabeth, TM-3/TM-4 slice)

Executable half: `lib/tray/` (`tray_shell.dart`, `quiet_hours.dart`,
`app_instance.dart`, `launch_login.dart`) + `assets/tray/` icons +
`test/tray_*_test.dart`. Design authority: Kira's
`docs/design/06-alert-tray-ux.md` §7 (states, menu, restore, denied /
opt-out); security boundary: `docs/decisions/003-tray-headless-security.md`;
headless contract: `docs/specs/headless-cli-contract.md` (untouched).

## What the shell is

The tray shell never polls by itself — it surfaces headless-tick /
in-app-rail results (`TrayShell.refresh`) and enforces quiet-hours at
the **notify layer** (the frozen headless tick always runs to
completion; toasts are suppressed here, so the inbox still collects
every firing signal and the 6 h flap suppression keeps working).

## Icon states (§7.1)

| State | Asset | Tooltip | When |
|---|---|---|---|
| `ok` | `tray-ok.png` (green + ✓) | `MyControlPanel — all clear` | last tick clean |
| `firing` | `tray-firing.png` (red + !) | `MyControlPanel — N alerts firing` | any unacked firing |
| `stale` | `tray-stale.png` (amber + clock) | `MyControlPanel — last checked Xm ago` / `Unlock to resume checks` (vault locked) | tick failed twice (§7.4) / backoff / vault locked |
| `quiet` | `tray-quiet.png` (grey crescent) | `MyControlPanel — quiet until HH:MM` | quiet-hours active |

Precedence: `stale > quiet > firing > ok` (crash honesty first: never a
green icon on a dead poller). Every state pairs color + glyph + text —
never color-only (Linux monochrome fallback: distinct glyphs;
`semanticLabel` mirrors the tooltip).

## Menu (§7.2, fixed order)

1. Status header (read-only): `● 2 firing · last checked 3m ago`
2. `Open MyControlPanel` → restore + focus the existing window
   (`mcp.open`)
3. `Mute until morning` / `Unmute` → one-shot mute until next 07:00
   (own pref `tray_muted_until_ms`; never rewrites the quiet window)
   (`mcp.mute.till_morning`)
4. `Check now` → restore the window (auto-refresh picks up within
   seconds); rate-limited to 1/min (`mcp.check_now`)
5. `Settings…` → restore the window (deep link to the Alerts section
   lands with Nurul's Settings IA, `t_7ba899fe` — follow-up, not this
   slice)
6. `Quit` → release the instance guard + exit (`mcp.quit`)

## Close box (§7.4) + single instance

- Consent ON ⇒ close hides to tray (+ one-time explainer toast
  "Minimised to tray — checks continue. Quit from the tray menu").
- Consent OFF ⇒ close quits for real.
- `AppInstanceGuard` (pure `dart:io`: OS file lock + loopback restore
  signal + in-process held-set): second launch signals the running
  instance to restore its window, then exits — exactly one window ever.
  Runs AFTER the `--poll-headless` gate in `main()`, so scheduled ticks
  are never blocked by it.

## Quiet hours (§5, notify-layer enforcement)

- Keys + window math are Kira's `QuietHours`
  (`lib/theme/alert_tokens.dart` — converged, not forked): default OFF,
  default window 22:00–07:00 local, wrap supported, `start == end` ⇒
  never quiet. Critical does NOT punch through in Beta.2. The tray adds
  only the one-shot `tray_muted_until_ms` pref + prefs I/O
  (`lib/tray/quiet_hours.dart`).
- Enforcement point: `DesktopAlerts.showFresh` / `showFreshPayload`
  (the single desktop notify funnel) consult `TrayQuietHours`
  and drop toasts while quiet/muted. Mobile rail untouched (follow-up).
- Mute toggle writes the one-shot pref only; the frozen tick is
  unaffected (exit 0/2/1 flows exactly as contracted).

## Launch at login (this slice, no new plugin)

`LaunchItemManager`: HKCU `…\Run` value via `reg` (never HKLM),
`~/.config/autostart/*.desktop`, `~/Library/LaunchAgents/
com.mycontrolpanel.login.plist` (never `/Library/LaunchDaemons`).
Artifacts carry the exe path only (secret-clean, pinned). The item
**follows the shared `background_alerts` consent** (ON ⇒ installed,
OFF ⇒ removed) — no second pref. Synced at launch; consent flips
during a session apply at next launch (foreground consent-change hook
is a follow-up with Nurul's Settings lane).

## Live-update wiring (status)

The tray repaints from `TrayShell.refresh` facts. This slice wires the
launch-time paint + menu callbacks; feeding *live* firing counts /
staleness into the running shell from the control-center fan-out (and
repaint on consent change) is a follow-up in Nurul's foreground lane —
the seam (`TrayShell.live?.refresh/repaint`) is ready and documented
here so that card needs no tray-file changes.

## What stays out (Beta.2 non-goals, carried over)

Remote push, exact-time guarantees, multi-window management (§8.5).
Severity-filtered toasts ("Critical only" default, §8.2) need
per-title severity the frozen headless payload does not carry —
TM-5 follow-up with Farah/Nurul, not this slice.
