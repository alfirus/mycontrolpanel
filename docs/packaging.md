# Commercial packaging — MyControlPanel

Status: **sales framing, not a license decision.** The license call lives in
PR #28 (Sofia: MIT + no paid tiers through v1-ship, `need-owner-decision`).
Nothing below overrules it. Until the owner signs PR #28, the only thing for
sale is nothing — the app is MIT-licensed (see `LICENSE`) and donations go via
`buy_me_a_coffee: alfirus`. Quote no prices, no SLAs, no paid entitlements.

Owner ruling 2026-10-28: the repo is PUBLIC and stays public. Internal-only
packaging is off the table.

## Tiers (Community live now; Pro / MSP proposed post-traction)

| | Community (live) | Pro (proposed) | MSP bundle (proposed) |
|---|---|---|---|
| Who | Homelab, evaluators, freelancers starting out | Freelancers + small teams with fleets | MSPs / SMEs managing client boxes |
| License | MIT, public repo | Paid, terms TBD (owner call) | Paid, terms TBD (owner call) |
| Price | RM 0, unlimited servers | TBD — quote nothing | TBD — quote nothing |
| Support | Community (issues, discussions) | Priority fixes + early feature votes (candidate) | Onboarding help + SLA response (candidate) |
| Candidate differentiators | — | Multi-team roles, audit export | Everything in Pro + managed alerting relay, client workspaces |
| Availability | Today | Post-traction only, needs Sofia + Finance sign-off | Post-traction only, needs Sofia + Finance sign-off |

Candidate Pro/MSP surface (from PR #28): multi-team roles, audit export,
managed alerting relay. These are roadmap candidates, not commitments —
never demo or promise them as built.

## What sales may promise today

- The MIT Community edition: full app, unlimited servers, local-first, no
  per-seat server costs on our side, OS-keychain credential storage.
- Honest capability framing per the README real-vs-roadmap matrix: metrics,
  crons, apps, alerts, logs, terminal, and AI chat are live over SSH;
  GitHub / CI-CD timeline / Security findings are UI-ready with wiring on
  the roadmap (GitLab equivalent is live).
- Donations/sponsorship as the only commercial path until v1-ship.

## What sales must never promise

- Any price, discount, SLA, onboarding commitment, or paid entitlement.
- That Pro/MSP features exist, have dates, or can be bought now.
- Background polling / push while closed, biometric lock enforcement, or
  Sentry/Datadog integrations (all roadmap — see README).
- Anything contradicting `docs/sales-one-pager.md` "What never to promise".

## Handoff

Pricing decision → Sofia (CEO) + Finance sign-off on PR #28 and
`docs/launch.md`. Messaging → Naura (CMO). Technical questions → via Sofia
to Maisarah's team. When PR #28 lands, update this file the same day.
