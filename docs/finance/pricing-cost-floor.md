# Pricing / Packaging — Cost-Floor Input (docs-side)

Owner: Finance & Accounts. Feeds future monetization docs. No prices promised here — only the
floor math any tier must clear. All rates are `TBD` placeholders; real rates live in finance workspace.

## Cost-floor formula

floor_per_seat_per_month = (server_per_seat + agent_per_node_share + api_per_seat + notify_per_seat + ci_share) x (1 + margin_buffer) + fixed_overhead_share

- Inputs come from `operating-cost-model.csv` bucket rates (same bucket names, no duplication).
- `margin_buffer` default assumption: 30% (covers variance + support); revisit before any price list.
- `fixed_overhead_share` = monthly fixed overhead / assumed paying seats.

## Tier-shape guidance (structure only, no figures)

| Tier | Intended scope | Floor implication |
|------|---------------|-------------------|
| Self-host / free | Customer infra, mock or own keys | floor near zero for us; support cost only |
| Team | Managed nodes + alert fan-out + GitHub wiring | full per-seat floor applies |
| Fleet / enterprise | Multi-region, rotation SLAs, audit retention | add secure_storage + audit-retention uplift |

## Rules for monetization docs

1. No tier price may sit below its computed floor; document the floor alongside every price draft.
2. Usage-based add-ons (extra nodes, extra notification volume) must reference the same bucket rates.
3. Any poll-interval or retention change triggers a floor re-check before packaging updates.
4. Proprietary rates and seat counts never enter the repo — link this file, keep numbers private.
