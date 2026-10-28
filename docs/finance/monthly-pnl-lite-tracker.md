# Monthly P&L-Lite Upkeep Tracker (template)

Owner: Finance & Accounts. One row per month; copy the CSV row each close. Amounts stay in the
finance workspace — the repo template carries structure and `0` placeholders only.

## Sections (companion CSV columns)

1. Income: MRR/add-ons collected that month.
2. Cost of delivery: server + agent + API + notifications + CI share (bucket totals from cost model).
3. Overhead: fixed overhead line + secure_storage rotations in-month.
4. Result: gross = income − delivery; net = gross − overhead; variance vs budget %.

## Monthly checklist

- [ ] Pull driver volumes (nodes, alerts, API calls, CI minutes) into cost model.
- [ ] Record income lines in finance copy (never in repo).
- [ ] Compute gross, net, budget variance; flag variance >15%.
- [ ] Roll gap statuses (G1–G4) forward; note any mock→live cutover in-month.
- [ ] File closed month; open next month's row from template zeros.

## Companion sheet

`monthly-pnl-lite-tracker.csv` — header + one `YYYY-MM` template row of zeros:
`month,income,budget_income,delivery_cost,overhead,gross,net,variance_pct,notes`.
Formulas: gross = income − delivery_cost; net = gross − overhead;
variance_pct = (net − budget_net) / budget_net once budget_net is set in finance copy.
