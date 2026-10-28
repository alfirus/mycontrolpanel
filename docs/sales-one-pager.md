# Sales one-pager — MyControlPanel (for Syafiqah)

Internal support doc, not customer-facing. Screen references point at
`lib/screens/` so demos always show real UI, never mockups.
Last synced: 2026-10-28 (main at PR #68).

## 30-second pitch

"MyControlPanel puts every server you look after on one pitch-black screen —
live metrics, cronjobs, apps, alerts, and logs over SSH, with a terminal
and an AI assistant built in. One codebase runs it on your laptop and your
phone, so the datacenter fits in your pocket."

## Use cases (each maps to a demo path)

| # | Buyer | Pain | Demo path (real UI) |
|---|---|---|---|
| 1 | Freelancer with 5–20 VPS boxes | 12 SSH tabs, missed cron failures | Overview grid → Server Details → Cronjobs tab (`control_center_screen.dart`, `server_details_screen.dart`): rescan crontabs live, open per-job log |
| 2 | Homelab / self-hoster | Wants Grafana insight without the stack | Metrics segment → metrics agent one-click install → live p95 chart (`agent_service.dart` + Metrics segment) |
| 3 | Small dev team | Deploys + infra in different tools | Deploys timeline + GitLab issues/MRs next to server health (Deploys + GitLab segments — note: deploys still demo data, GitLab live) |
| 4 | On-call / after-hours | 3 a.m. "disk full" pages | Alerts segment: disk ≥80/90%, failed units, brute-force SSH; foreground watcher badge + snack |
| 5 | Security-conscious SME | Credentials scattered in notes | Settings screen: servers/keys/PATs in OS keychain (`flutter_secure_storage`), keys pasted or picker-imported, passphrase-per-visit |

## Objection handling

| Objection | Answer (honest) | Screen to show |
|---|---|---|
| "Is this just a dashboard mockup?" | No — metrics, crons, apps, alerts, logs, terminal, and AI chat are live over SSH today. Only GitHub, CI/CD timeline, and Security findings are UI-ready with wiring on the roadmap. Full matrix in README. | Server Details LIVE banner; rescan a crontab live |
| "Why not Grafana / Netdata / Uptime Kuma?" | Those are server-side stacks you install and maintain per box. This is one client app, zero server-side stack beyond a stdlib-only Python agent installed in one click. And it adds terminal + AI + GitLab in the same window. | One-click agent install dialog + install log |
| "Where do my credentials go?" | Nowhere off-device. Stored in the OS keychain/keystore, never in plain prefs; private keys stored as content, never paths; encrypted-key passphrase asked once per visit. | Settings screen + key-passphrase dialog |
| "Does it work on my phone?" | Same codebase ships iOS + Android. Phone demo in README (`hero-phone.png`). | Phone screenshot / `flutter run -d ios` |
| "What does it cost?" | MIT-licensed app, local-first, no per-seat server costs on our side. Commercial tiers (Pro/Team) are undecided — quote nothing until Sofia + Finance sign `docs/launch.md` pricing. | `docs/launch.md` pricing table (TBD) |
| "GitHub / CI-CD / Security look finished — are they?" | Honest answer: UI-ready, API wiring on the roadmap. GitLab equivalent IS live. Never demo GitHub/CI-CD/Security as live. | README status matrix |

## What never to promise

- Background polling / push while the app is closed (roadmap, not built).
- Biometric app lock enforcement (toggle exists; enforcement needs `local_auth`).
- Sentry/Datadog integrations (placeholder row only).
- Specific prices or SLAs (owner decision pending).

## Handoff

Questions on messaging → Naura (CMO). Anything needing a demo build or
engineering detail → via Sofia to Maisarah's team. Keep this file in sync
with the README matrix when segments flip from UI-ready to live.
