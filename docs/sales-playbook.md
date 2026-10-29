# Sales playbook — MyControlPanel (outbound starter)

Owner: Syafiqah (Sales Manager). Status: starter kit for a pre-traction,
$0 MIT Community edition — every sequence below sells a free trial + a demo,
never a paid tier (no prices exist; see `docs/packaging.md`, PR #28).

## ICPs (ideal customer profiles)

| # | ICP | Why they bite | Where to find them | First demo hook |
|---|---|---|---|---|
| 1 | Freelancer / fractional DevOps, 5–20 VPS boxes | 12 SSH tabs, missed cron failures | Indie-hacker / self-hosted communities, X, Reddit r/selfhosted | Rescan their crontab live on the call |
| 2 | Homelab / self-hoster | Grafana insight without the stack | r/homelab, Homelab forums, YouTube comments | One-click agent install → live p95 chart |
| 3 | Small dev team (2–15), ships on GitLab | Deploys + infra in different tools | GitLab groups, startup Slack/Discord | GitLab MRs next to server health |
| 4 | On-call engineer / SRE side-project | 3 a.m. disk-full pages | SRE/DevOps meetups, on-call Twitter | Alert badge + per-job cron log |

Disqualify fast: needs SSO/audit-export/compliance reporting (Pro/MSP
candidates, not built), needs push-while-closed or mobile-device-management
(roadmap), or asks for a price/SLA (none exist — log interest for post-v1).

## Sequences + cadence (5 touches, 14 days)

Day 0 — cold first touch (use `templates/outreach/01-cold-first-touch.md`).
Day 2 — value bump: one screenshot (`docs/screenshots/overview.png`) + one
honest line ("metrics/crons/alerts live; GitHub + CI/CD UI-ready, wiring next").
Day 5 — demo offer (use `03-demo-invite.md`): 15-min live rescan of THEIR
crontab or agent install on a staging box.
Day 9 — breakup-or-nurture (use `02-followup-bump.md`): permission to check
back post-v1.
Day 14 — close the loop: mark Won/Lost in the pipeline file, note the reason.

Rules: max 5 touches per prospect per cycle; every touch adds one proof
(screenshot, matrix row, or demo path) — never "just bumping"; stop on
unsubscribe instantly; log every touch with date in the pipeline file
(`sales-pipeline-YYYY-MM.md` convention: New Lead > Contacted > Qualified >
Proposal Sent > Negotiation > Won/Lost).

## Demo script (15 min, real UI only)

1. (2 min) Overview grid — "every server, one glance."
2. (4 min) Drill one server — live metrics + sparkline + p95.
3. (4 min) Rescan a crontab live, open a per-job log.
4. (3 min) Alerts segment — badge + snack on a firing signal.
5. (2 min) Terminal + AI chat with fleet context; Settings keychain line.
   Never demo GitHub/CI-CD/Security as live — show + label UI-ready.

## Handoff

Messaging questions → Naura (CMO). Demo-build or deep technical questions →
via Sofia to Maisarah's team. Pipeline + revenue status → Sofia.
