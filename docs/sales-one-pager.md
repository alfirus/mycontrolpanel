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

## ROI pitch (Syafiqah add-on, 2026-10-28)

For the buyer who asks "what is this worth to me" — frame time, not money
(no prices exist to discount; see `docs/packaging.md` + PR #28).

**The math (illustrative, say "for example" out loud):** a freelancer babysitting
10 VPS boxes burns ~30 min/day hopping SSH tabs to eyeball disks, crons, and
failed units. One screen with live alerts + per-job cron logs + one-click agent
install compresses that to a ~5-minute glance — roughly 2 hours/week back, or
~100 hours/year. At any contractor rate, that dwarfs a $0 MIT download; the
honest close is "try Community free, measure your own week back."

**Screenshot strip for the pitch** (all real UI, never mockups):
`docs/screenshots/overview.png` → `docs/screenshots/server-details.png` →
hero lifestyle `assets/marketing/hero-laptop.png` / `hero-phone.png`.
Demo order: Overview grid → drill one server → rescan a crontab live →
show the alert badge. If the room asks for GitHub/CI-CD/Security, show the
screens AND say "UI-ready, wiring on roadmap" in the same breath.

**One-line closes per buyer** (reuse the use-case table above):
1. Freelancer: "Twelve tabs become one glance — and missed cron failures page you first."
2. Homelab: "Grafana insight with none of the stack — one click installs the agent."
3. Small team: "Deploys and infra health in the same window your GitLab already lives in."
4. On-call: "The 3 a.m. disk-full finds you at 11 p.m. instead."
5. Security-conscious SME: "Every credential leaves your notes for the OS keychain."

## Handoff

Questions on messaging → Naura (CMO). Anything needing a demo build or
engineering detail → via Sofia to Maisarah's team. Keep this file in sync
with the README matrix when segments flip from UI-ready to live.
