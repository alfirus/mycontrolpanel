# Store listing copy — MyControlPanel (DRAFT, internal)

Status: draft for Sofia + Naura sign-off. Nothing here is published until the
release tag, real screenshots, and pricing sign-off exist (see
`docs/sales-kit-review.md` launch blockers). Voice: direct, technical, zero
hype. Every line must stay true to the README real-vs-roadmap matrix.

## Shared short description (≤80 chars, all stores)

Every server. One glance. Live metrics, crons, alerts over SSH.

## Shared long description (base; trim per store)

MyControlPanel is a pitch-black IT Control Center for your servers. Connect
over SSH and see live metrics, cronjobs, apps, alerts, and logs refresh into
one calm dashboard (manual rescan / tab switch), with a built-in terminal and
an AI assistant that knows your fleet (bring your own provider key or run
Ollama locally).

Live today: server metrics via a one-click stdlib-only agent, cron/app/alert
discovery over SSH, real log tail, terminal, live GitLab issues and MRs.
UI-ready with wiring on the roadmap: GitHub, CI/CD timeline, Security
findings — each labelled DEMO in-app until wired. Background alerting is an
explicit opt-in (default OFF, ~15 min cadence, on-device only, no push
relay). Credentials stay in the OS keychain; the app is MIT-licensed,
local-first, with no account and no tracking.

## Per-store notes

- Google Play: short desc 80 chars; full desc ≤4000 chars (use base trimmed).
  Feature graphic 1024×500 + icon required. No `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
  declared (deliberate) — declare only `POST_NOTIFICATIONS` + `USE_BIOMETRIC`.
  Data-safety answers live in `privacy-permissions.md`.
- Apple App Store: subtitle ≤30 chars ("Every server. One glance.").
  Keywords ≤100 chars: `ssh,server monitor,homelab,cron,devops,uptime,sre`.
  Needs privacy-nutrition answers + `NSFaceIDUsageDescription` purpose string
  (already in Info.plist). Background `BGTaskScheduler` identifier must match
  the registered task or iOS throws at runtime.
- Snap Store: description from base; confinement declaration must match the
  build (strict preferred — document plugs: network, network-bind for LAN
  agent reads). No snapcraft.yaml exists yet — packaging is Beta.2 TM-2/TM-8
  scope (#125); do not list until the snap builds from CI.
- Microsoft Store: description from base; no elevation, per-user install
  only (matches ADR-003 scheduler posture). No MSIX exists yet — same rule
  as snap: no listing until the package builds from CI.

## What never appears in a listing

Prices, SLAs, "push notifications", "real-time streaming", GitHub/CI-CD/
Security as live features, or any testimonial not collected from a real user.
