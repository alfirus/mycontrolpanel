# Sales kit v1 — MyControlPanel (for Syafiqah)

Owner: Naura (CMO) · Sign-off required: Syafiqah (kit safety for live
calls), Sofia (voice). Status: draft — SAFE for freelancer/homelab
soft-launch calls selling a free MIT trial + live demo ONLY after the
fixes below are read. NOT safe for any paid conversation or promise in
writing beyond "MIT, RM0, community support."

Sources: `docs/sales-one-pager.md`, `docs/sales-playbook.md`,
`docs/launch.md`, `docs/packaging.md`, `docs/sales-kit-review.md`
(conditional-GO verdict + fixes, all applied here),
`docs/user/background-alerting.md` (shipped beta.1 behavior),
`docs/finance/BUDGET-beta.md` + `docs/finance/pricing-cost-floor.md`
(pricing guardrails). Screen pointers aim at `lib/` so demos show real
UI, never mockups.

## 1. One-pager (leave-behind, one page when printed)

**MyControlPanel — every server, one glance.**

Pitch-black, cross-platform IT Control Center (macOS, Windows, Linux,
iOS, Android — one Flutter codebase). Connect over SSH and see live
metrics, cronjobs, apps, alerts, and logs refresh into one calm
dashboard (manual rescan / tab switch), with a built-in terminal and an
AI assistant that knows your fleet (bring your own provider key or run
Ollama locally).

Live today: metrics via one-click stdlib-only agent, cron/app/alert
discovery over SSH, real log tail, terminal, live GitLab issues + MRs.
UI-ready with wiring on the roadmap (bannered DEMO in-app): GitHub,
CI/CD timeline, Security findings. Background alerts are an explicit
opt-in (default OFF, ~15 min, on-device, no push relay). Credentials in
the OS keychain. MIT-licensed, local-first, no account, no tracking.

Try it free: https://github.com/alfirus/mycontrolpanel

## 2. Three use cases (demo-led, real UI only)

| # | Buyer | Pain | 3-minute demo path |
|---|---|---|---|
| 1 | Freelancer, 5–20 VPS boxes | 12 SSH tabs, missed cron failures | Overview grid → Server Details → Cronjobs tab: rescan crontabs live, open a per-job log. Close: "Twelve tabs become one glance — and missed cron failures page you first." |
| 2 | Homelab / self-hoster | Wants signal without the stack | Metrics segment → one-click agent install → live p95 chart. Frame honestly: "lightweight live metrics + p95; not a Grafana replacement (no retention/export yet)." Close: "Signal with none of the stack — one click installs the agent." |
| 3 | On-call engineer | 3 a.m. disk-full pages | Alerts segment → badge + snack on a firing signal → Settings toggle with consent copy ("Polls your servers every ~15 min in the background.") + "last checked …" staleness line. Close: "Opt into background alerts and the 3 a.m. disk-full finds you at 11 p.m. instead." |

Demo order for any call: Overview grid → drill one server → rescan a
crontab live → show the alert badge. If the room asks for GitHub /
CI-CD / Security, show the screens AND say "UI-ready, wiring on
roadmap" in the same breath. Never demo Deploys as live (demo data);
the GitLab segment is the live one.

## 3. Five-slide outline (soft-launch deck)

1. Title — "Every server. One glance." + hero (`assets/marketing/hero.png`).
   One line: pitch-black IT Control Center, MIT, local-first.
2. The pain — 12 SSH tabs; missed cron failures; 3 a.m. disk-full.
   (No invented stats — speak from the buyer's day, not a survey.)
3. The product, live — 3 screenshots, all real UI: Overview grid,
   Server Details, Alerts segment. Each bullet carries its honesty
   label (DEMO banners named where they exist).
4. Trust: credentials + consent — OS keychain storage; background
   alerts opt-in OFF by default with the exact consent copy; "last
   checked …" staleness line; no push relay, no account, no tracking.
5. Try it free — MIT Community, RM0, unlimited servers, community
   support. CTA: repo link + 15-minute live demo offer (rescan THEIR
   crontab or install the agent on a staging box). No prices, no SLAs.

## 4. Pricing narrative — DRAFT, INTERNAL ONLY

Do NOT publish, paste into proposals, or read verbatim on calls. The
only line a prospect may hear: "MIT Community edition — full app,
unlimited servers, RM0, community support."

- Today (live): Community — MIT, public repo, RM0, donations/sponsorship
  the only commercial path until v1-ship (per `docs/packaging.md` + PR
  #28 owner ruling). Per-seat server costs on our side: ~0 (local-first).
- Proposed (post-traction ONLY): Pro (freelancers/small teams) and MSP
  bundle — tiers, prices, SLAs all TBD, need Sofia + Finance sign-off on
  `docs/launch.md` pricing. Candidate differentiators (never demo or
  promise as built): multi-team roles, audit export, managed alerting
  relay.
- Guardrails sales must respect: any future tier must clear the cost
  floor in `docs/finance/pricing-cost-floor.md`; beta break-even is
  donations vs amortized launch fees (~11 USD/mo base — see
  `docs/finance/BUDGET-beta.md` break-even note). Quote NO prices or
  SLAs on calls — log interest for post-v1, point pricing questions at
  Syafiqah.

## 5. Objection handling

| Objection | Answer (honest) | Show |
|---|---|---|
| "Is this just a mockup?" | No — metrics, crons, apps, alerts, logs, terminal, AI chat are live over SSH today. Only GitHub, CI/CD timeline, Security findings are UI-ready. | Rescan a crontab live; LIVE banners |
| "Why not Grafana / Netdata?" | Those are server-side stacks you install per box. This is one client app + a stdlib-only agent installed in one click, plus terminal + AI + GitLab in the same window. Not a Grafana replacement (no retention/export yet). | One-click install dialog + log |
| "Where do my credentials go?" | Nowhere off-device. OS keychain/keystore; private keys stored as content, never paths; encrypted-key passphrase asked once per visit. | Settings screen |
| "Will it wake me at 3 a.m.?" | Only if you opt in: Settings → Background alerts (default OFF, "~15 min in the background", on-device local notifications, honest "last checked …" staleness — never silent). No push relay, no exact-time guarantees; iOS may deliver hours apart. Desktop wakes with the window closed only after tray mode lands (Beta.2). | Toggle + staleness line (`docs/user/background-alerting.md`) |
| "Does it work on my phone?" | Same codebase ships iOS + Android. | Phone screenshot / `flutter run -d ios` |
| "What does it cost?" | MIT app, RM0, community support. Commercial tiers undecided — quote nothing until Sofia + Finance sign. | `docs/launch.md` pricing table (TBD) |
| "GitHub / CI-CD / Security look finished?" | UI-ready, wiring on the roadmap. GitLab equivalent IS live. | README status matrix |

## 6. What never to promise

Remote push, "real-time" or exact-time delivery, desktop closed-app
alerts before tray mode ships (Beta.2 gate), biometric lock enforcement
detail beyond the Settings toggle, Sentry/Datadog integrations, specific
prices or SLAs, or any testimonial not collected from a real user. ROI
math stays illustrative-only: always spoken "for example" + "measure
your own week back" — never pasted into a proposal as a researched
claim.

## Handoff

Kit safety → Syafiqah (sign here before the first call). Voice →
Sofia. Demo builds / deep technical questions → via Sofia to
Maisarah's team. Pricing → Sofia + Finance. Launch content companion:
`docs/marketing/launch-content.md`. Visual assets: Hana
(`assets/store/`, card `t_c8b233d4`). Store fields: `docs/store/`.
