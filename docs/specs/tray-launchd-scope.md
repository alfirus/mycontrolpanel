# macOS scope decision: LaunchAgent, not menu-bar-only (Elizabeth, TM-3)

Decision (slice recommendation, pending Aisyah signing spike + Lina
privilege-scope review): ship closed-app polling on macOS as a
**per-user LaunchAgent** invoking the frozen headless tick, with the
**app itself as the menu-bar/tray helper** when it runs. No bare
LaunchDaemon, no second helper binary in Beta.2.

## Why this scope

`docs/design/05-background-alerting.md` §8.1 sketches "a menu-bar/tray
helper instead of a bare LaunchAgent". Two readings were possible:

- (a) The helper is a separate always-on process that owns polling.
- (b) The helper is the app's own tray shell; polling is the scheduler
  invoking the installed binary's `--poll-headless` flag.

This slice picks (b):

1. One headless pipeline everywhere (Lina's TM-1 contract): Windows
   Task Scheduler, systemd user timer, and the macOS agent all invoke
   the same `mycontrolpanel[.exe] --poll-headless` argv with the same
   exit codes and stdout. A separate helper process would fork the
   pipeline and need its own Alya review.
2. ADR-003 already pins per-user scope + no elevation + vault-only
   reads. A per-user `~/Library/LaunchAgents/com.mycontrolpanel.poll.plist`
   (`StartInterval` 900, exact `--poll-headless` argv — Lina's
   `scripts/headless/macos/` template, contract-pinned) satisfies it
   with zero new review surface.
3. The tray shell (`lib/tray/tray_shell.dart`, `tray_manager` +
   `window_manager`) already owns the icon + menu + restore behavior
   Kira's §7 assigns to "the helper" — no second binary needed to meet
   the UX spec.

## Artifacts (this slice)

| Artifact | Scope | Owner |
|---|---|---|
| `scripts/headless/macos/com.mycontrolpanel.poll.plist` (poll every 15 min) | per-user LaunchAgent (existing, Lina — reused, not re-templated) | Lina / Zara lifecycle on top |
| `~/Library/LaunchAgents/com.mycontrolpanel.login.plist` (boot the app) | per-user login item, app-managed (`lib/tray/launch_login.dart`, label `com.mycontrolpanel.login`) | Elizabeth (this slice) |
| Signing / notarisation notes | Aisyah spikes the path; fallback recorded below | Aisyah |

The login label is deliberately distinct from the poll label so Zara's
lifecycle tooling and the app never fight over one plist.

## Fallback (if signing blocks the agent)

Per Rina's plan risk 3: fallback is menu-bar-only (tray shell, no
LaunchAgent) and the Beta.2 gate records the reduced scope explicitly.
The app still polls while open (in-app timer) and the login item still
boots it; only window-closed polling on macOS drops to "app must be
open". No code change needed to take the fallback — skip the agent
install step in the runbook.

## Open questions (not blockers for this slice)

1. Aisyah: confirm Developer-ID signing + notarisation path for the
   `.app` so the LaunchAgent child process inherits a clean TCC
   posture (network client entitlement already present; notifications
   need first-fire user allow — unchanged).
2. Lina (privilege-scope review, per card): confirm the login plist
   above stays inside ADR-003 §5 (per-user, no elevation, exe path
   only — no flags/tokens). No scheduler-argv change is proposed.
3. Balqis (TM-6): matrix row for macOS covers agent-installed +
   agent-absent (fallback) + vault-locked skip.
