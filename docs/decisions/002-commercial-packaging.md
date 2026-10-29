# Decision 002 (RATIFIED 2026-10-29): License + paid tiers

Status: **ratified** — owner approved MIT + donations through v1 (2026-10-29);
paid tiers revisit post-traction. Label `need-owner-decision` removed on merge.

## Context

Current de-facto posture is **public open-source with donations**: MIT license
(`LICENSE`), public repo, `buy_me_a_coffee: alfirus` funding link, and a
reddit-ready public framing (PR #7). No paywall, no license key, no telemetry,
no paid tier exists in the codebase (`publish_to: none` only blocks accidental
pub.dev publishing — it is not a commercial control). There is no
"Private — all rights reserved" line anywhere in the repo (verified across all
branches 2026-10-28); the only "private" wording in-tree refers to
cryptographic private keys and a pubspec template comment.

## Options (post-ruling)

| | OSS + donations (status quo) | Paid / freemium |
|---|---|---|
| Distribution | public MIT repo | public core + paid Pro |
| Cost to run | zero | licensing/entitlement infra |
| Growth | community, homelab word-of-mouth | revenue, support burden |
| Fit for v1 | matches reality today | premature before traction |

License alternatives to MIT (e.g. Apache-2.0) change patent-grant posture but
nothing material for a self-hosted admin tool at this stage — no reason to
churn the license.

## Proposal

**Keep MIT, no paid tiers through v1-ship.** Rationale: the repo is already
public and positioned for homelab/self-hosted users; monetisation infra (keys,
tiers, paywalled features) would slow v1 for a product with no users yet.
Revisit paid options only after v1 traction, with candidate Pro surface:
multi-team roles, audit export, managed alerting relay.

This PR adds a short Positioning section to the README so the posture is
stated publicly.

## Resolution

**MIT, no paid tiers through v1-ship — ratified by owner 2026-10-29.**
Pro/MSP bundles remain post-traction concepts (docs/packaging.md) with no
prices and no sale dates.
