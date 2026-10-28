# Decision 002 (PROPOSAL — needs owner sign-off): Commercial packaging — internal-only vs OSS vs paid

Status: **proposed** — not final until the owner approves.
Label: `need-owner-decision`.

## Context

Current de-facto posture is **open-source with donations**: MIT license
(`LICENSE`), public repo, `buy_me_a_coffee: alfirus` funding link, and a
reddit-ready public framing (PR #7). No paywall, no license key, no telemetry,
no paid tier exists in the codebase (`publish_to: none` only blocks accidental
pub.dev publishing — it is not a commercial control).

## Options

| | Internal-only | OSS + donations (status quo) | Paid / freemium |
|---|---|---|---|
| Distribution | private repo or binaries | public MIT repo | public core + paid Pro |
| Cost to run | zero | zero | licensing/entitlement infra |
| Growth | none | community, homelab word-of-mouth | revenue, support burden |
| Fit for v1 | hides an already-public repo | matches reality today | premature before traction |

## Proposal

**Stay MIT-licensed OSS with Buy-Me-a-Coffee donations through v1-ship.**
Rationale: the repo is already public and positioned for homelab/self-hosted
users; monetisation infra (keys, tiers, paywalled features) would slow v1 for
a product with no users yet. Revisit paid options only after v1 traction, with
candidate Pro surface: multi-team roles, audit export, managed alerting relay.

This PR also adds a short Positioning section to the README so the posture is
stated publicly.

## Owner question

@alfirus — please approve or reject: **MIT OSS + donations through v1, revisit
paid post-traction?** If you prefer internal-only or paid now, say so and this
note will be rewritten before merge.
