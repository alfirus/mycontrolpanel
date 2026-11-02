# Pilot pricing — 3 tiers, MIT self-hosted positioning (Sales Kit v1)

Owner: Syafiqah (Sales Manager) · Pricing authority: Sofia (CEO) +
Finance (Nafisah) · Status: go-live framing.
DRAFT — INTERNAL ONLY. Do NOT publish, paste into proposals, or read
verbatim on calls. The only line a prospect may hear: "MIT Community
edition — full app, unlimited servers, RM0, community support."
Ratified base: `docs/decisions/002-commercial-packaging.md` (MIT, no
paid tiers through v1-ship). Cost-floor rule:
`docs/finance/pricing-cost-floor.md`. Budget inputs:
`docs/finance/BUDGET-beta.md`.

## The rule (read first)

There are no prices to quote until Sofia + Finance sign. Every pilot
below sells a free Community trial + a live demo. Any future paid tier
must clear its computed cost floor (30% margin buffer) *plus* the
amortized launch share — Syafiqah owns that math when the time comes;
this file owns the framing, not figures.

## 3-tier pilot framing (positioning, not a price list)

| | Community pilot (live today) | Pro pilot (proposed, post-traction) | MSP bundle (proposed, post-traction) |
|---|---|---|---|
| Who | Homelab, freelancers, SMB evaluators, MSP trial fleets | Freelancers + small teams with fleets | MSPs / SMEs managing client boxes |
| License | MIT, public repo | Paid, terms TBD (owner call) | Paid, terms TBD (owner call) |
| Price | RM 0, unlimited servers | TBD — quote nothing | TBD — quote nothing |
| Support | Community (issues, discussions) + sales-manager attention during pilot; no SLA | Priority fixes + early feature votes (candidate) | Onboarding help + SLA response (candidate) |
| Candidate differentiators | — | Multi-team roles, audit export | Everything in Pro + managed alerting relay, client workspaces |
| Availability | Today | Post-traction only, needs Sofia + Finance sign-off | Post-traction only, needs Sofia + Finance sign-off |

Candidate Pro/MSP surface comes from the owner ruling — roadmap
candidates, not commitments. Never demo or promise them as built.

## Break-even anchor (Finance inputs — internal)

Beta break-even = donations vs amortized launch fees
(`docs/finance/BUDGET-beta.md` §6): ~11 USD/mo base (136/yr), ~2 USD/mo
lean, ~19 USD/mo worst. Monthly burn is 0 while free-tier guardrails
hold. Feeding the tier math later: floor_per_seat_per_month =
(server + agent-node share + api + notify + ci share) × 1.30 +
fixed-overhead share (`docs/finance/pricing-cost-floor.md`).

## What to say when asked about price

- "Community is MIT and free — unlimited servers, no seat meter on our
  side because it runs on your devices over your SSH."
- "Paid tiers are undecided — no prices, no SLAs, no dates. I'll log
  your interest and come back post-v1."
- Never: discount a price that doesn't exist, imply a Pro ship date, or
  put ROI money-math in a proposal as a researched claim.

## Pilot commercials (what goes in the proposal)

Per `docs/proposal-template.md` §6: license MIT (`LICENSE`), unlimited
servers; pilot effort time-boxed with no SLA implied; support during
pilot = community + sales-manager attention, no SLA. Log paid-interest
for post-v1 follow-up; record the outcome in the pipeline file.

## Handoff

Pricing decision → Sofia + Finance. Messaging → Naura. Technical depth →
via Sofia to Maisarah's team. Pipeline + revenue → Sofia.
