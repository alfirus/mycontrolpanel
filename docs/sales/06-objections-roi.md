# Objection sheet + ROI vs RMM (Sales Kit v1)

Owner: Syafiqah (Sales Manager) · Messaging: Naura (CMO) · Status: go-live.
Answer the objection honestly, show the screen, stop there. Sources of
truth: README real-vs-roadmap matrix, `docs/user/background-alerting.md`
(consent + staleness), `docs/runbooks/secrets-hardening.md` (security),
`docs/finance/BUDGET-beta.md` (break-even). Never promise: remote push,
"real-time"/exact-time delivery, desktop closed-app alerts before tray
mode (Beta.2), prices, SLAs, testimonials, or invented stats.

## Objections (answer + show)

| Objection | Answer (honest) | Show |
|---|---|---|
| "Is this just a mockup?" | No — metrics, crons, apps, alerts, logs, terminal, AI chat are live over SSH today. Only GitHub, CI/CD timeline, Security findings are UI-ready. | Rescan a crontab live; LIVE banners |
| "Why not Grafana / Netdata?" | Those are server-side stacks you install and maintain per box. This is one client app + a stdlib-only agent installed in one click, plus terminal + AI + GitLab in the same window. Lightweight live metrics + p95 — not a Grafana replacement (no retention/export yet). | One-click install dialog + install log |
| "Why not my RMM (NinjaOne / Datto / Atera)?" | RMMs are agent-fleets with a vendor cloud, per-seat billing, and rollout projects. This is a local-first client app: your SSH, your keychain, no vendor cloud, no telemetry, no seat meter — MIT and free to pilot in 10 minutes. Trade-off we state openly: no managed push relay, no multi-tenant client console, no compliance reporting (Pro/MSP candidates, roadmap). See ROI vs RMM below. | Settings keychain line; overview grid |
| "Where do my credentials go?" | Nowhere off-device. OS keychain/keystore via `SecureStore`; private keys stored as content, never paths; encrypted-key passphrase asked once per visit; agent tokens auto-provisioned per host, never displayed; logs pass through `SecretHygiene.redactForLog`. | Settings screen + key-passphrase dialog |
| "Will it wake me at 3 a.m.?" | Only if you opt in: Settings → Background alerts (default OFF). Read the consent line verbatim: "Polls your servers every ~15 min in the background." On-device local notifications, no push relay, no exact-time guarantees — iOS may deliver hours apart. Desktop wakes with the window closed only after tray mode lands (Beta.2). | Toggle + "last checked …" staleness line |
| "How stale is the data?" | The app never pretends to be fresher than it is: every surface shows "last checked …" (just now / N min / N hr / N days), written on every tick — even all-fail ticks. If the line says hours, the data is hours old: open the app to force a poll. Background ticks cover your first 10 servers, 15 s per-host cap; repeats of the same alert re-notify at most every 6 h. | Staleness line in Settings + alerts surface |
| "Does background polling drain battery / spy on me?" | Leave it OFF and nothing polls in the background: no network, no vault touch, no notifications; turning it OFF later stops future ticks. ON: short-lived polls on your existing connection, no keep-alive; Android batches via WorkManager (Doze), the app never requests battery exemption; a locked vault denies background credential reads (fail closed). | Consent copy + battery guidance in `docs/user/background-alerting.md` |
| "Does it work on my phone?" | Same codebase ships iOS + Android. | Phone screenshot / `flutter run -d ios` |
| "What does it cost?" | MIT app, RM0, unlimited servers, community support. Commercial tiers undecided — quote nothing until Sofia + Finance sign; log interest for post-v1. | `docs/launch.md` pricing table (TBD) |
| "GitHub / CI-CD / Security look finished?" | UI-ready, wiring on the roadmap. GitLab equivalent IS live. | README status matrix |
| "Is there an audit trail / compliance story?" | AI actions carry an append-only audit trail (capped at 200, viewable in the chat drawer). No SOC 2 / ISO certs, no pen-test report, no SSO/audit-export — offer the runbook + code paths, never a certificate we don't hold. | Chat drawer audit viewer |
| "What about Sentry / crash reporting?" | Opt-in crash reporter in Settings → Integrations (default OFF, DSN in the OS keychain, test-event verifies delivery). Datadog sink is future. | Integrations toggle |

## ROI vs RMM (illustrative only — spoken, never pasted as a claim)

Rules from the kit review: always spoken "for example" + "measure your
own week back" — never pasted into a proposal as a researched claim, no
invented stats, no testimonials.

**The math (say "for example" out loud):** a freelancer babysitting 10
VPS boxes burns ~30 min/day hopping SSH tabs to eyeball disks, crons,
and failed units. One screen with live alerts + per-job cron logs +
one-click agent install compresses that to a ~5-minute glance — roughly
2 hours/week back, or ~100 hours/year. At any contractor rate, that
dwarfs a $0 MIT download; the honest close is "try Community free,
measure your own week back."

**RMM comparison (for the buyer who has one):**

| | Typical RMM | MyControlPanel Community |
|---|---|---|
| Model | Vendor cloud + per-seat billing + rollout | Local-first client app, MIT, RM0, unlimited servers |
| Setup | Agent fleet + console provisioning | One-click stdlib agent per host, 10-min pilot |
| Data path | Via vendor servers (telemetry by design) | Your SSH only; no telemetry, no account, no vendor cloud |
| Alerts | Managed push relay, SLAs | Opt-in on-device alerts, honest staleness, no relay (tray mode Beta.2) |
| Compliance | SSO, audit export, reports | Not built — Pro/MSP candidates, roadmap only |
| Best fit | Fleets needing managed compliance + SLAs today | Freelancers, homelab, small teams, MSP pilots wanting one glance without the stack |

Close: "If you need managed compliance with an SLA today, keep the RMM —
we're not that yet. If you want one free screen over your boxes this
afternoon, that's the pilot."

## Handoff

Messaging questions → Naura (CMO). Technical depth → via Sofia (CEO) to
Maisarah's team. Pricing → Sofia + Finance. Pipeline + revenue → Sofia.
