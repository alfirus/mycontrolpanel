# Launch content — MyControlPanel beta public launch

Owner: Naura (CMO) · Sign-off required: Sofia (voice). Status: draft —
nothing here is published until the release tag, re-captured
screenshots, pricing sign-off, and 1–2 real testimonials exist (see
`docs/sales-kit-review.md` launch blockers). Voice: direct, technical,
zero hype. Every claim stays true to the README real-vs-roadmap matrix
and `docs/user/background-alerting.md`.

## 1. Release-notes polish (beta.1 draft entry)

```text
MyControlPanel v1.0.0-beta.1 — foreground alert rail + mobile
background slice.

- Foreground watcher: bell badge + snack bar naming fresh signals
  (failed units, disk ≥80/90%, brute-force SSH, load, kernel errors,
  reboots), max 3 + "…and N more".
- Background alerts (explicit opt-in, default OFF): on-device local
  notifications, ~15 min cadence, honest "last checked …" staleness.
  No push relay, no account, no tracking.
- Desktop in-app alert rail on Windows/Linux/macOS (same path, same
  payload). Closed-app desktop delivery arrives with tray mode
  (Beta.2) — not in this release.
- Credentials stay in the OS keychain; AI assistant needs your own
  provider key or a local Ollama instance.
- GitHub, CI/CD timeline, Security findings remain UI-ready with
  wiring on the roadmap (bannered DEMO in-app).

MIT-licensed, local-first, free. Community support on GitHub.
```

## 2. Hero copy (sign-off-ready, replaces `docs/launch.md` draft lines)

- Headline: Every server. One glance.
- Subhead: MyControlPanel is a pitch-black IT Control Center for
  macOS, Windows, Linux, iOS, and Android. Connect over SSH and watch
  metrics, cronjobs, apps, alerts, and logs refresh into one calm
  dashboard (manual rescan / tab switch) — plus a terminal and an AI
  assistant that already knows your fleet (bring your own key or run
  Ollama locally).
- Primary CTA: Get the app (links to Releases once `v1.0.0-beta.1` is cut).
- Secondary CTA: Read the docs (README → How it works).
- Trust line (under CTA): MIT · No account · No tracking · Credentials
  stay in your OS keychain.
- Hero visual: `assets/marketing/hero.png` (lifestyle alternates:
  `hero-laptop.png`, `hero-phone.png`).

## 3. Social posts

### X / Twitter (3-post thread)

1. Every server. One glance. MyControlPanel beta is live: metrics,
   crons, apps, alerts, logs over SSH — one pitch-black screen, plus
   terminal + AI with fleet context. MIT, local-first, no account.
   [hero.png]
2. Honest labels only: GitHub / CI-CD / Security screens are UI-ready
   with wiring on the roadmap — bannered DEMO in-app until wired.
   What ships today is real SSH data, not mockups. [server-details.png]
3. Background alerts are opt-in (default OFF, ~15 min, on-device, no
   push relay) with an honest "last checked" line. Try the beta free:
   [releases link once cut]

### LinkedIn

MyControlPanel beta.1 is out — a pitch-black IT Control Center for
people who look after servers. Connect over SSH: live metrics via a
one-click stdlib-only agent, cron/app/alert discovery, real log tail,
built-in terminal, and an AI assistant grounded in your fleet (BYO key
or local Ollama). Credentials stay in the OS keychain; no account, no
tracking; MIT-licensed. Background alerting is an explicit opt-in
(default OFF, on-device only). Roadmap is public, UI-ready screens are
labelled DEMO — no hype. [link once live]

### Reddit (r/selfhosted-style — read the promo rules first, no drive-by)

Title: [Self-hosted tool I built] One dashboard for all my VPS boxes —
metrics, crons, alerts over SSH (beta, MIT, local-first)

Body: Hey all — long-time lurker. I look after a handful of VPS boxes
and got tired of 12 SSH tabs, so I built MyControlPanel: one Flutter
app (Linux/Windows/macOS/Android/iOS) that connects over SSH and shows
metrics (one-click stdlib agent), crontabs with per-job logs, systemd /
Docker / ports, alert signals, and real log tail, plus a terminal and
an AI chat that knows your boxes (BYO key or Ollama). MIT, no account,
no tracking, creds in the OS keychain. Honest state: GitHub/CI-CD/
Security screens are UI mockups labelled DEMO until wired; background
alerts are opt-in. Happy to answer anything — and brutal feedback
welcome.

## 4. Newsletter issue (beta announcement)

Subject: Beta.1 is live — every server, one glance

Hello — MyControlPanel beta.1 is out.

What it does: one pitch-black screen for all your servers. Live
metrics, cronjobs, apps, alerts, and logs over SSH, with a terminal and
an AI assistant that knows your fleet.

What's new in beta.1: the foreground alert rail (badge + snack on fresh
signals) and the mobile background slice — opt-in local notifications
with an honest "last checked" line. No push relay, ever.

What's honestly not done: GitHub / CI-CD / Security wiring (DEMO
banners in-app), closed-app desktop alerts (tray mode, Beta.2), pricing
beyond free MIT Community.

Try it: [releases link]. Reply with your worst SSH-tabs story — the
best one gets… our gratitude, and a bug fix named after you. (No
invented testimonials, ever.)

— Naura

## 5. Sixty-second demo script (for Hana — shot list + voiceover)

Total 60 s. All captures on the release-candidate commit with a real
connected server (LIVE banners visible). Foreground only — nothing here
shows background/closed-app behavior.

| Time | Shot (real UI) | Voiceover |
|---|---|---|
| 0–8 s | Overview grid, servers live | "Every server. One glance. MyControlPanel watches all your boxes from one pitch-black screen." |
| 8–18 s | Drill into Server Details: metrics + sparkline + p95 | "Live metrics over SSH — CPU, RAM, disk, latency — installed with a one-click agent." |
| 18–30 s | Cronjobs tab: rescan live, open per-job log | "Crons discovered live. Rescan any box, open any job's log." |
| 30–40 s | Alerts segment: badge + snack firing | "Firing signals find you first — failed units, disk pressure, brute-force SSH — while the app is open." |
| 40–50 s | Terminal + AI chat with fleet context | "A terminal in your pocket, and an AI that already knows your fleet." |
| 50–60 s | Settings: keychain line + background toggle OFF + hero end-card | "Credentials stay in your keychain. Background alerts are opt-in, off by default. Free, MIT, local-first — every server, one glance." |

On-screen honesty labels (burned in, not footnotes): "GitHub / CI-CD /
Security: DEMO — wiring on roadmap" whenever those screens appear (or
cut them); "Background alerts: opt-in" on the toggle shot. End card:
repo URL + "Beta.1 — MIT". Music: none / neutral bed. Captions: full
VO as captions (accessibility + silent autoplay).

## Handoff

Voice → Sofia (sign here before anything ships). Sales execution →
Syafiqah (`docs/marketing/sales-kit-v1.md`). Visuals → Hana (renders
the §5 shots + `assets/store/` pack, card `t_c8b233d4`). Store fields →
`docs/store/`. Release mechanics → Burhanah (`docs/release-gates.md`).
