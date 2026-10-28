# Operating Cost Model — MyControlPanel (docs-side)

Owner: Finance & Accounts. Status: template with placeholder rates only — NO proprietary numbers in repo.
Fill real unit rates in the finance workspace copy; this file defines buckets, drivers, and formulas.

## Cost buckets

| # | Bucket | What it covers | Cost driver | Unit |
|---|--------|----------------|-------------|------|
| 1 | Server / hosting | VMs, containers, regions running the control plane and agents | provisioned vCPU-hours + GB-months per region | rate/hour, rate/GB-mo |
| 2 | Agent runtime | On-device agent (poll, SSH exec, log tail, metrics history) | managed nodes x poll cadence | rate/node-mo |
| 3 | Notifications | Alert push/fan-out (alert_watch paths) | alerts delivered per severity | rate/1k deliveries |
| 4 | API usage | GitHub/GitLab REST + Actions polling, AI assist calls | API calls per seat per day | rate/1k calls |
| 5 | Secure storage ops | secure_storage / key rotation overhead (cutover exec) | rotations per quarter | flat/rotation |
| 6 | CI / tooling | analyze+test minutes, artifact storage | CI minutes per PR | rate/minute |

## Monthly cost formula

monthly_total = SUM over buckets (driver_volume x unit_rate) + fixed_overhead

- Fixed overhead covers licences, domains, standby capacity; recorded as one line in the CSV.
- Volumes come from product telemetry (nodes, alerts, API calls, CI minutes); rates come from vendor price pages.

## Companion sheet

`operating-cost-model.csv` — one row per bucket with columns:
`bucket,driver,volume_unit,volume_placeholder,unit_rate_placeholder,monthly_formula,notes`.
All volumes and rates are `0` / `TBD` placeholders by design.

## Review cadence

Revisit quarterly or when a driver moves >20% (new region, poll interval change, notification volume spike).
