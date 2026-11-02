# MyControlPanel — every server, one glance (one-pager source)

Customer-facing single page. Mirror of `docs/sales-kit/one-pager.pdf`
(verbatim — the PDF is the leave-behind; this file is the diffable source).
Messaging owned by Naura (CMO); claims pinned to `docs/store/listing-copy.md`
and the README real-vs-roadmap matrix. Voice: direct, technical, zero hype.

## Headline

Every server. One glance.

## Subhead

MyControlPanel is a pitch-black IT Control Center for macOS, Windows,
Linux, iOS, and Android. Connect over SSH and see live metrics, cronjobs,
apps, alerts, and logs refresh into one calm dashboard (manual rescan /
tab switch) — plus a built-in terminal and an AI assistant that knows your
fleet (bring your own provider key or run Ollama locally).

## Live today

- Server metrics via a one-click stdlib-only agent (`:9108`).
- Cron/app/alert discovery over SSH; real log tail with level filters.
- Built-in SSH terminal + AI chat with fleet context.
- Live GitLab issues + MRs next to server health.

## Honestly labelled (in the product, in this order)

- GitHub, CI/CD timeline, Security findings: UI-ready, wiring on the
  roadmap — each labelled DEMO in-app until wired. Never demoed as live.
- Background alerts: explicit opt-in, default OFF, ~15 min cadence,
  on-device local notifications with an honest "last checked …" line.
  No push relay, no exact-time promise (iOS may deliver hours apart).
- Desktop closed-app delivery arrives with tray mode (Beta.2) — planned,
  not shipped; foreground rail (badge + snack, max 3 + "…and N more")
  is what ships today.
- Credentials stay in the OS keychain; no account, no tracking.
- MIT-licensed, local-first, free. Community support on GitHub (no SLA).
  Commercial tiers undecided — nothing priced or promised here.

## Try it free

https://github.com/alfirus/mycontrolpanel

MIT · No account · No tracking · Credentials stay in your OS keychain.
