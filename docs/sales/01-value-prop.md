# Value prop — MyControlPanel (one page, leave-behind)

Owner: Syafiqah (Sales Manager) · Messaging: Naura (CMO) · Status: go-live.
Voice: direct, technical, zero hype. Every claim below matches the README
real-vs-roadmap matrix and `docs/roadmap.md` — if a screen is UI-ready,
say so in the same breath.

## Headline

**MyControlPanel — every server, one glance.**

A pitch-black IT Control Center for macOS, Windows, Linux, iOS, and
Android — one Flutter codebase. Connect over SSH and watch live metrics,
cronjobs, apps, alerts, and logs refresh into one calm dashboard (manual
rescan / tab switch), with a built-in terminal and an AI assistant that
already knows your fleet (bring your own provider key or run Ollama
locally).

## Why it exists

Small teams and MSPs look after fleets with 12 SSH tabs, missed cron
failures, and 3 a.m. disk-full pages. Server-side stacks (Grafana,
Netdata) answer this with per-box infrastructure you must install and
maintain. MyControlPanel answers it with one client app plus a
stdlib-only Python agent installed in one click — no monitoring stack,
no account, no tracking.

## What is live today (demo any of this)

- Live metrics via one-click stdlib-only agent (`:9108`, verified
  `GET /metrics`) with p95 chart — lightweight live metrics, not a
  Grafana replacement (no retention/export yet).
- Cronjobs discovered live over SSH (`crontab`, `/etc/crontab`,
  `/etc/cron.d/*`) with per-job logs and last-run tracking.
- Apps: systemd units, Docker containers, listening ports, plus top
  processes via agent v2 `/procstats`.
- Alerts: failed units, disk ≥80/90%, brute-force SSH, load, kernel
  errors, reboots — bell badge + snack while the app is open; background
  alerts are an explicit opt-in (default OFF, ~15 min, on-device only,
  no push relay) with an honest "last checked …" staleness line.
  Desktop closed-app delivery arrives with tray mode (Beta.2) — never
  demo it as shipped.
- Real log tail (journal/syslog/docker) over SSH; built-in SSH + local
  terminal per server; AI chat with fleet context and a capped audit
  trail; GitLab issues/MRs live next to server health.
- Credentials in the OS keychain/keystore (`SecureStore`), never in
  plain prefs; SSH keys stored as content, never paths.

## Honest scope (say in the same breath)

GitHub / CI-CD timeline / Security findings screens are UI-ready with
wiring on the roadmap — bannered DEMO in-app until wired. No remote
push, no exact-time delivery, no SSO/audit-export, no Sentry/Datadog
beyond the opt-in crash reporter (Datadog sink is future). Full matrix:
README "What works today vs what's next" + `docs/roadmap.md`.

## Commercial position

MIT Community edition — full app, unlimited servers, RM0, community
support. No paid tiers through v1-ship (owner-ratified,
`docs/decisions/002-commercial-packaging.md`). This pilot sells a free
trial + a live demo, never a price or SLA. Pricing detail:
`docs/sales/03-pilot-pricing.md`.

## Try it free

Repo: https://github.com/alfirus/mycontrolpanel — 15-minute live demo
offer: we rescan YOUR crontab or install the agent on a staging box.
Demo script: `docs/sales/04-demo-script-10min.md`.

## Handoff

Messaging questions → Naura (CMO). Technical depth → via Sofia (CEO) to
Maisarah's team. Pricing → Sofia + Finance. Pipeline + revenue → Sofia.
