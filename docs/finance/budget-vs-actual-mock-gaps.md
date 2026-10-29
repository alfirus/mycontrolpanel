# Budget-vs-Actual — MOCK-to-Real Gaps (docs-side)

Owner: Finance & Accounts. Placeholder figures only — tracks the cost/schedule impact of
closing each mock gap, not live credentials or spend. Source of gaps: `lib/models/mock_data.dart`
consumers (`github_service`, `alert_watch`, `secure_store`, Actions/deploy timeline).

## Gap register

| # | Gap | Mock today | Real target | Budget line affected |
|---|-----|-----------|-------------|----------------------|
| G1 | GitHub API | `GithubItem` fixtures | Live REST (issues/PRs/comments) | api_usage: REST calls/seat/day |
| G2 | Actions timeline | `DeployItem` fixtures (runId live-only) | Actions runs API + run timeline | api_usage + CI minutes |
| G3 | Alert polling | `AlertItem` fixtures | Live poll/push fan-out | notifications: deliveries/severity |
| G4 | secure_storage | Key-loader stubs | Rotation + prune + wipe cutover | secure_storage_ops: rotations/qtr |

## Budget-vs-actual method

1. Budget = placeholder unit rate x forecast volume per gap line (CSV column `budget_amount=TBD`).
2. Actual = metered volume once the gap closes x same rate.
3. Variance = actual − budget; flag any line >15% for reforecast.
4. Mock-phase rows stay at zero volume: mocks cost nothing, so actual = 0 until cutover.

## Companion sheet

`budget-vs-actual-mock-gaps.csv` — columns:
`gap_id,gap,metric,budget_volume,budget_rate_placeholder,budget_amount,actual_volume,actual_amount,variance_formula,status`.
All amounts `TBD`/`0` placeholders.

## Close-out rule

When a gap closes (live wiring merged), move its row from `mock` to `live` status and start
metering actuals the same month. Keep one closed-gap row per quarter for audit.
