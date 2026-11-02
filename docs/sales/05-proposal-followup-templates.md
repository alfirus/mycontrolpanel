# Proposal + follow-up templates (Sales Kit v1)

Owner: Syafiqah (Sales Manager) · Status: go-live.
Rules: copy per prospect, fill every `{{bracket}}`, delete the instruction
lines before sending. Nothing here quotes a price or SLA — none exist
until Sofia + Finance sign (`docs/packaging.md`, PR #28). Max 5 touches
per prospect per cycle, 14 days; every touch adds one proof (screenshot,
matrix row, demo path) — never "just bumping"; stop on unsubscribe
instantly; log every touch with date in the pipeline file.
Master proposal structure: `docs/proposal-template.md` (per-prospect
copies build from it — scope table, deployment, security FAQ).

## Template A — proposal (Community pilot)

Subject: MyControlPanel Community pilot — {{scope_one_liner}}

Hi {{first_name}},

What I heard: {{fleet_size}} boxes ({{os_mix}}), managed via
{{current_tooling}}. Pain: {{pain_1}}; {{pain_2}}. Success looks like:
{{success_criteria}}.

Pilot (time-boxed, no SLA implied):

| Week | Activity | Done means |
|---|---|---|
| 1 | Install Community edition on {{seats}} machines; connect {{pilot_hosts}} pilot hosts | Overview grid live on real hosts |
| 1–2 | One-click metrics-agent install per pilot host (`:9108`, stdlib-only Python) | Live metrics + p95 chart per host |
| 2 | Cron discovery review + per-job log walkthrough | Every crontab accounted for |
| 2–3 | Alert tuning (disk ≥80/90%, failed units, brute-force, load, kernel, reboots) | Badge + snack verified on a real signal |
| 3 | Terminal + AI-chat walkthrough (your own provider key or local Ollama) | Your POC runs a session unaided |

Out of scope (saying so upfront): background polling/push while closed,
desktop closed-app delivery (tray mode, Beta.2), biometric detail beyond
the Settings toggle, Sentry/Datadog beyond the opt-in crash reporter,
GitHub / CI-CD timeline / Security-findings API wiring (UI-ready,
roadmap — GitLab equivalent is live).

Commercials: MyControlPanel Community is MIT-licensed and free —
unlimited servers, community support, no license fee to quote. Any paid
terms are undecided; if you want them later I'll log it for post-v1.

Acceptance: (1) Overview grid live on {{pilot_hosts}} hosts. (2) Every
crontab discovered with per-job logs openable. (3) Alert badge + snack on
a real firing signal. (4) Go / no-go recorded; paid-interest (if any)
logged for post-v1.

— Syafiqah, Sales @ MyControlPanel

## Template B — cold first touch (Day 0)

Subject: every server, one glance (free MIT app)

Hi {{first_name}},

Noticed {{trigger}} — guessing SSH-tab overload comes with the territory.

MyControlPanel puts every server on one pitch-black screen: live metrics,
cronjobs, apps, alerts, and logs over SSH, plus a terminal and an AI
assistant that already knows your fleet. MIT-licensed, free, unlimited
servers — one codebase runs it on your laptop and your phone.

Honest scope: metrics, crons, apps, alerts, logs, terminal, and AI chat
are live over SSH today. GitHub / CI-CD timeline / Security findings are
UI-ready with wiring on the roadmap (GitLab equivalent is live). Full
matrix in our README — nothing presented as live unless it is.

Worth a 10-min demo? I'll rescan a crontab live on a box of your choice
(script: `docs/sales/04-demo-script-10min.md`).

— Syafiqah, Sales @ MyControlPanel

## Template C — value bump (Day 2)

Subject: Re: every server, one glance (+ one screenshot)

Hi {{first_name}},

Floating this back up with the one screenshot that sells it best: our
Overview grid (attached — real UI, `docs/screenshots/overview.png`).

The pitch in one line for {{icp_type}}: {{one_line_close}}.

Still MIT, still free, still no paid tier to dodge — and the background
story is consent-first: alerts poll on-device about every 15 minutes only
if you opt in, and the app always shows how stale the data is.

— Syafiqah

## Template D — demo invite (Day 5)

Subject: 10 min — I'll rescan YOUR crontab live

Hi {{first_name}},

Demo offer, concrete: 10 minutes, your staging box (or ours), and I will:

1. Install the metrics agent in one click (stdlib-only Python, port 9108).
2. Rescan your crontabs live and open a per-job log.
3. Show the alert badge firing on a real signal.

Screens: `lib/screens/control_center_screen.dart`,
`lib/screens/server_details_screen.dart`. No slides, no mockups.

Two slots: {{slot_1}} or {{slot_2}} — or name a time and I'll make it work.

— Syafiqah, Sales @ MyControlPanel

## Template E — breakup-or-nurture (Day 9)

Subject: close the loop? (one word is fine)

Hi {{first_name}},

Last nudge from me: if the timing's off, may I check back after our v1?
One word and I'll close the loop on my side — no hard feelings, and no
further touches until you say so.

If it helps later: Community stays MIT and free, and the pilot offer
above has no expiry games attached.

— Syafiqah

## Template F — close the loop (Day 14, internal + optional send)

Internal: mark Won/Lost in the pipeline file with the reason
(`sales-pipeline-YYYY-MM.md` convention: New Lead > Contacted >
Qualified > Proposal Sent > Negotiation > Won/Lost). Paid-interest (if
any) logged for post-v1. Optional send: "Closing the loop on my side —
the pilot offer stands whenever you're ready. Thanks for the time."

## Handoff

Messaging questions → Naura (CMO). Technical depth → via Sofia (CEO) to
Maisarah's team. Pipeline + revenue status → Sofia.
