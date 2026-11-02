# Store listing copy — MyControlPanel

Status: draft for Sofia + Naura sign-off. Nothing here is published
until the release tag, real screenshots, and pricing sign-off exist
(see `docs/sales-kit-review.md` launch blockers). Voice: direct,
technical, zero hype. Every line stays true to the README
real-vs-roadmap matrix and to `docs/user/background-alerting.md`.
Tray-mode closed-app desktop delivery (Beta.2) is NOT claimed
anywhere below — it is planned, not shipped.

Character limits verified at write time with `wc -m` (see counts
after each block). Re-verify if you edit a line.

## Shared short description (all stores — 63 chars, limit 80)

Every server. One glance. Live metrics, crons, alerts over SSH.

## Shared long description (base — ~780 chars, fits Play 4000 / App Store 4000)

MyControlPanel is a pitch-black IT Control Center for your servers.
Connect over SSH and see live metrics, cronjobs, apps, alerts, and
logs refresh into one calm dashboard, with a built-in terminal and an
AI assistant that knows your fleet (bring your own provider key or
run Ollama locally).

Live today: server metrics via a one-click stdlib-only agent,
cron/app/alert discovery over SSH, real log tail, terminal, and live
GitLab issues and MRs. UI-ready with wiring on the roadmap: GitHub,
CI/CD timeline, Security findings — each labelled DEMO in-app until
wired. Background alerting is an explicit opt-in (default OFF,
~15 min cadence, on-device only, no push relay). Credentials stay in
the OS keychain; the app is MIT-licensed, local-first, with no
account and no tracking.

## Google Play

- Short description (63/80): use the shared short description verbatim.
- Full description: use the shared base verbatim (~780/4000 chars).
- Feature graphic 1024x500 + app icon required (see screenshot checklist).
- Permissions declared: `POST_NOTIFICATIONS` (runtime prompt on API
  33+, requested when the background toggle flips on),
  `USE_BIOMETRIC` (app-lock only). Deliberately NOT declared:
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `RECEIVE_BOOT_COMPLETED`
  (battery exemption stays a manual user step — see the user guide).
- Data-safety answers: `privacy-permissions.md` (Play section).

## Apple App Store

- App name: MyControlPanel.
- Subtitle (25/30): `Every server. One glance.`
- Keywords (49/100): `ssh,server monitor,homelab,cron,devops,uptime,sre`
- Description: use the shared base verbatim (~780/4000 chars).
- Privacy-nutrition answers + `NSFaceIDUsageDescription` purpose
  string (already in Info.plist: biometric app lock).
- Background `BGTaskScheduler` identifier
  `com.mycontrolpanel.my_control_panel.backgroundAlerts` must match
  the registered task or iOS throws at runtime — verified in
  `Info.plist` + `AppDelegate.swift` + `BackgroundAlerts.taskName`.

## Snap Store

- Description: use the shared base verbatim.
- Confinement declaration must match the build (strict preferred —
  document plugs: network, network-bind for LAN agent reads). No
  snapcraft.yaml exists yet — packaging is Beta.2 TM-2/TM-8 scope
  (#125); do not list until the snap builds from CI.
- Daemons: none. Tray-mode systemd user timers (Beta.2) are per-user
  units installed by script, not snap daemons — state this in the
  listing notes.

## Microsoft Store

- Description: use the shared base verbatim.
- No elevation, per-user install only (matches ADR-003 scheduler
  posture). No MSIX exists yet — same rule as snap: no listing until
  the package builds from CI.
- No background-task declaration while tray mode ships as Task
  Scheduler scripts (Beta.2); declare a Windows background task ONLY
  if a UWP component lands — it has not.

## Support (all stores — paste into the listing support field)

- Support URL: https://github.com/alfirus/mycontrolpanel/issues
- Promise only: "Community support on GitHub (MIT, RM0). No SLA."
  Paid tiers are undecided — quote nothing until Sofia + Finance sign
  `docs/launch.md` pricing (`docs/sales-one-pager.md` break-even note).

## Screenshot captions (all stores — each under 120 chars)

1. Overview grid: "Every server on one pitch-black screen — live metrics over SSH."
2. Server details: "Drill into any server: metrics, alerts, apps, cronjobs, logs."
3. Cronjobs: "Rescan crontabs live and open per-job logs."
4. Alerts: "Firing signals with honest staleness — background opt-in, default OFF."
5. Terminal: "Built-in SSH terminal next to the dashboard — no tab-hopping."

Captures must be re-taken from the release-candidate commit with a
real connected server (LIVE banners, never demo-only grids):
`docs/store/screenshot-checklist.md`. Never mockups, never stale UI.

## What never appears in a listing

Prices, SLAs, "push notifications", "real-time streaming", GitHub /
CI-CD / Security as live features, tray-mode closed-app desktop
alerts as shipped, or any testimonial not collected from a real user.
