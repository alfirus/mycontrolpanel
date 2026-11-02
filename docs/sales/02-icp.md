# ICP — ideal customer profiles (Sales Kit v1)

Owner: Syafiqah (Sales Manager) · Messaging: Naura (CMO) · Status: go-live.
Source: `docs/sales-playbook.md` ICPs, extended with SMB/MSP buyers for
the v1 kit. Disqualify fast — every "not a fit" below protects live calls.

## Who we sell to (ranked)

| # | ICP | Fleet | Why they bite | Where to find them | First demo hook |
|---|---|---|---|---|---|
| 1 | Freelancer / fractional DevOps | 5–20 VPS boxes | 12 SSH tabs, missed cron failures | Indie-hacker / self-hosted communities, X, Reddit r/selfhosted | Rescan their crontab live on the call |
| 2 | Homelab / self-hoster | 3–10 own boxes | Lightweight live metrics + p95 with none of the stack (not a Grafana replacement — no retention/export yet) | r/homelab, homelab forums, YouTube comments | One-click agent install → live p95 chart |
| 3 | Small dev team (2–15), ships on GitLab | 5–30 boxes + GitLab | Deploys + infra in different tools; GitLab MRs live next to server health (Deploys timeline is demo data — say so) | GitLab groups, startup Slack/Discord | GitLab MRs next to server health |
| 4 | On-call engineer / SRE side-project | On-call rotation | 3 a.m. disk-full pages; opt-in background alerts find it at 11 p.m. instead | SRE/DevOps meetups, on-call Twitter | Alert badge + per-job cron log |
| 5 | SMB, security-conscious (10–100 staff) | 5–40 boxes, no dedicated SRE | Credentials scattered in notes; every secret leaves notes for the OS keychain; read-only-by-enforcement SSH setup | Local SME meetups, MSP referrals | Settings keychain line + read-only `monitor`-user runbook (`docs/runbooks/read-only-access.md`) |
| 6 | MSP managing client boxes (pilot only) | Multiple client fleets | One glance per client without per-box stacks; Community pilot proves the workflow before any paid bundle exists | MSP Slack/Discord, partner intros | Overview grid per client + alert badge on a real signal |

## What each ICP hears (one-line closes)

1. Freelancer: "Twelve tabs become one glance — and missed cron failures page you first."
2. Homelab: "Lightweight live metrics with none of the stack — one click installs the agent."
3. Small team: "Deploys and infra health in the same window your GitLab already lives in."
4. On-call: "Opt into background alerts and the 3 a.m. disk-full finds you at 11 p.m. instead."
5. SMB: "Every credential leaves your notes for the OS keychain — enforced read-only SSH available."
6. MSP: "One screen per client fleet, free to pilot — managed relay and client workspaces stay roadmap candidates, never promises."

## Disqualify fast (not a fit today)

- Needs SSO / audit-export / compliance reporting → Pro/MSP candidates, not built. Log interest for post-v1, move on.
- Needs push-while-closed, exact-time delivery, or MDM → roadmap (tray mode Beta.2). Move on.
- Asks for a price, discount, or SLA → none exist until Sofia + Finance sign. Log interest for post-v1, move on.
- Needs Datadog/Sentry integration beyond the opt-in crash reporter → Datadog sink is future. Move on.
- Wants GitHub/CI-CD/Security as live integrations today → UI-ready, wiring on roadmap. Offer the GitLab-live path or move on.

## Fit checklist (qualify in 5 minutes)

- [ ] 3+ Linux boxes reachable over SSH (or willing staging box for the demo)?
- [ ] Pain is tab-hopping, missed crons, or late alerts (not compliance)?
- [ ] Accepts MIT Community + community support (no SLA) for the pilot?
- [ ] Decision-maker on the call or booked within the 14-day sequence?

Qualified → proposal path (`docs/sales/05-proposal-followup-templates.md`).
Unqualified → log Lost with reason in the pipeline file, check back post-v1.

## Handoff

Messaging questions → Naura (CMO). Technical depth → via Sofia (CEO) to
Maisarah's team. Pipeline + revenue status → Sofia.
