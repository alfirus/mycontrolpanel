# Launch landing copy — MyControlPanel (DRAFT)

Status: draft for owner review. Nothing here is published copy until Sofia
signs off. Voice: direct, technical, zero hype. Every claim must stay true
to the README real-vs-roadmap matrix — if a feature is UI-ready, say so.

## Hero

**Headline:** Every server. One glance.

**Subhead:** MyControlPanel is a pitch-black IT Control Center for macOS,
Windows, Linux, iOS, and Android. Connect over SSH and watch metrics,
cronjobs, apps, alerts, and logs stream into one calm dashboard —
plus a terminal and an AI assistant that already knows your fleet.

**Primary CTA:** Get the app (links to Releases once `v0.1.0` is cut)
**Secondary CTA:** Read the docs (README → How it works)

**Hero visual:** `assets/marketing/hero.png`
(lifestyle alternates: `hero-laptop.png`, `hero-phone.png`)

## Feature blocks (homepage order)

1. **Live server metrics** — CPU / RAM / disk, latency, uptime, sparklines.
   One-click metrics-agent install over SSH; no separate monitoring stack.
2. **Cronjobs, discovered** — every crontab on every box, with last-run
   tracking and per-job logs. Edit schedules without leaving the app.
3. **Apps & processes** — systemd units, Docker containers, listening ports,
   plus top processes via the v2 agent. Know what's running, everywhere.
4. **Alerts that find you first** — failed units, disk pressure, brute-force
   SSH, load spikes, kernel errors, reboots. Badge + snack the moment they fire.
5. **Real log tail** — journal, syslog, and Docker logs streamed live over SSH
   with level filters. Demo heartbeat when no servers are connected.
6. **Terminal in your pocket** — full SSH + local shell per server, on desktop
   and mobile. Copy-pasteable SSH commands for everything the app does.
7. **AI assistant with fleet context** — streaming answers grounded in your
   servers, with tool calling and an audit trail. Bring your own key or run
   Ollama locally.
8. **GitLab, wired in** — issues, MRs, and tasks live in the same view as
   your infrastructure. (GitHub + CI/CD timeline: UI-ready, wiring next —
   say this on the page, not in a footnote.)

## Pricing-tier draft (needs owner decision)

| Tier | Price (draft) | For | Includes |
|---|---|---|---|
| Free / Self-hosted | RM 0 | Homelab, evaluators | Full app, unlimited servers, community support |
| Pro | TBD (owner call) | Freelancers, small teams | Everything + priority fixes, early feature votes |
| Team / Business | TBD (owner call) | MSPs, SMEs | Everything in Pro + onboarding help, SLA response |

> Do NOT publish prices without Sofia + Finance sign-off. The Free tier is
> safe to promise (MIT-licensed, local-first, no server costs on our side).

## Social proof placeholders (fill before launch)

- [ ] 1–2 homelab user quotes (ask early testers; no invented testimonials).
- [ ] Screenshot strip: `docs/screenshots/overview.png`,
      `docs/screenshots/server-details.png`.
- [ ] Launch cards: `assets/marketing/social/` (3× 16:9 + 1× 1:1).

## Launch checklist

- [ ] `v0.1.0` tag cut; release artifacts attached (`release.yml`).
- [ ] Social preview image uploaded (see CHANGELOG owner actions).
- [ ] Homepage URL set on repo + this page deployed.
- [ ] Pricing decision signed (Sofia + Finance).
- [ ] Sales one-pager reviewed by Syafiqah (`docs/sales-one-pager.md`).
