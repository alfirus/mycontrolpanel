# 10-minute demo script — live UI only (Sales Kit v1)

Owner: Syafiqah (Sales Manager) · Messaging: Naura (CMO) · Status: go-live.
Setup: release-candidate build, one real connected server (LIVE banners
visible), foreground only — nothing here shows closed-app behavior.
Screenshots (all real UI, never mockups): `docs/screenshots/overview.png`,
`docs/screenshots/server-details.png`, lifestyle
`assets/marketing/hero-laptop.png` / `assets/marketing/hero-phone.png`.
Screen pointers aim at `lib/` so demos show real UI, never slides.

## Pre-call (5 min before)

- [ ] Connected staging box (theirs or ours) over SSH; agent installed or ready to install live.
- [ ] A firing signal available to show (disk ≥80%, a failed unit, or brute-force sample) — badge + snack need something real.
- [ ] Settings → Background alerts OFF (show the default), keychain line visible.
- [ ] GitHub / CI-CD / Security tabs open only if asked — with "UI-ready, wiring on roadmap" in the same breath.

## Minute-by-minute

| Time | Show (real UI) | Say |
|---|---|---|
| 0:00–1:30 | Overview grid, servers live | "Every server. One glance. MyControlPanel watches all your boxes from one pitch-black screen." |
| 1:30–3:30 | Drill into Server Details: live metrics + sparkline + p95 | "Live metrics over SSH — CPU, RAM, disk, latency — installed with a one-click agent. Lightweight live metrics plus p95; not a Grafana replacement, no retention or export yet." |
| 3:30–5:30 | Cronjobs tab: rescan a crontab LIVE, open a per-job log | "Crons discovered live. Rescan any box, open any job's log — this is the missed-cron-failure killer." Rescan THEIR crontab if they brought one. |
| 5:30–7:00 | Alerts segment: badge + snack firing on the real signal | "Firing signals find you first — failed units, disk pressure, brute-force SSH — while the app is open." |
| 7:00–8:30 | Settings: keychain line + Background toggle OFF + staleness line | "Credentials stay in your keychain. Background alerts are opt-in, off by default — it polls your servers about every 15 minutes on-device, no push relay, and this 'last checked' line tells you exactly how stale the data is." Read the consent copy verbatim: "Polls your servers every ~15 min in the background." |
| 8:30–9:30 | Terminal + AI chat with fleet context | "A terminal in your pocket, and an AI that already knows your fleet — bring your own key or run Ollama locally." |
| 9:30–10:00 | Close per ICP (`docs/sales/02-icp.md` one-line closes) + next step | "MIT, free, unlimited servers, community support. Next step: a Community pilot on your staging boxes — no price, no SLA, just your week back to measure." |

## If they ask for GitHub / CI-CD / Security

Show the screen AND say "UI-ready, wiring on the roadmap" in the same
breath. Never demo Deploys as live (demo data); the GitLab segment is
the live one. Point at the README matrix — nothing presented as live
unless it is.

## If they ask about background / closed-app alerts

- Mobile: opt-in local notifications, ~15 min cadence, on-device only,
  no push relay; iOS may deliver hours apart — the staleness line is the
  contract (`docs/user/background-alerting.md`).
- Desktop closed-app delivery arrives with tray mode (Beta.2) — not in
  this release. Never demo it as shipped.

## Never do on a demo

- No mockups, no "representative" screenshots — real UI or it doesn't go on screen.
- No price, discount, SLA, or Pro/MSP date — log interest for post-v1.
- No testimonial you didn't collect from a real user. No invented stats.
- ROI math spoken "for example" + "measure your own week back" only —
  never pasted as a researched claim.

## Handoff

Demo-build or deep technical questions → via Sofia (CEO) to Maisarah's
team. Messaging → Naura. Follow-up sequence:
`docs/sales/05-proposal-followup-templates.md`.
