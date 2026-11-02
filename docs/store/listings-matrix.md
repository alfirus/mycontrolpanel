# Store listings matrix — MyControlPanel

Status: draft for Sofia (voice) + Syafiqah (kit alignment) sign-off.
Nothing here is published until the release tag, re-captured screenshots,
and pricing sign-off exist (see `docs/sales-kit-review.md` launch blockers).
Voice: direct, technical, zero hype. Every line stays true to the README
real-vs-roadmap matrix — UI-ready features are labelled, never sold as live.

Sources of truth: `docs/store/listing-copy.md` (base copy),
`docs/store/privacy-permissions.md` (questionnaire answers),
`docs/store/screenshot-checklist.md` (capture freshness),
`docs/roadmap.md` + README matrix (live vs UI-ready),
`docs/sales-kit-review.md` (conditional-GO fixes — applied below).

## 1. App identity (all stores)

| Field | Value | Constraint |
|---|---|---|
| App name | MyControlPanel | Apple ≤30 chars (14 used) |
| Apple subtitle | Every server. One glance. | ≤30 chars (26 used) |
| Publisher | alfirus | — |
| Category (Play / Apple) | Tools (primary); Productivity (secondary) | — |
| Category (Snap / Microsoft) | System / Utilities | — |
| Price | Free, RM 0 (MIT-licensed, local-first) | Never list a paid tier until Sofia + Finance sign `docs/launch.md` pricing |

## 2. Short descriptions

Shared short (Play short desc + shared tagline, ≤80 chars):

```text
Every server. One glance. Live metrics, crons, alerts over SSH.
```

Per-store application:

- Google Play short description (≤80 chars): use the shared short verbatim.
- Apple subtitle (≤30 chars): `Every server. One glance.`
- Snap / Microsoft summary line: use the shared short verbatim.

## 3. Long descriptions

### 3a. Google Play full description (use verbatim, ~1,900 chars, limit 4,000)

```text
MyControlPanel is a pitch-black IT Control Center for your servers.
Connect over SSH and see live metrics, cronjobs, apps, alerts, and logs
refresh into one calm dashboard (manual rescan / tab switch), with a
built-in terminal and an AI assistant that knows your fleet (bring your
own provider key or run Ollama locally).

LIVE TODAY
- Server metrics (CPU / RAM / disk, latency, uptime, sparklines) via a
  one-click stdlib-only agent install over SSH.
- Cronjobs discovered live across every box, with per-job logs.
- Apps and processes: systemd units, Docker containers, listening ports.
- Alerts that find you first while the app is open: failed units, disk
  pressure, brute-force SSH, load spikes, kernel errors, reboots
  (foreground badge + snack; no background polling while closed).
- Real log tail (journal, syslog, Docker) streamed live over SSH.
- Terminal in your pocket: full SSH + local shell per server.
- Live GitLab issues and MRs next to your infrastructure health.

HONESTLY LABELLED
GitHub, the CI/CD deployment timeline, and Security findings are UI-ready
with wiring on the roadmap — each is bannered DEMO in-app until wired.
Background alerting is an explicit opt-in (default OFF, ~15 min cadence,
on-device only, no push relay). The AI assistant needs your own provider
key or a local Ollama instance.

PRIVACY
No account, no tracking, no ads. Server addresses and credentials stay in
your device's OS keychain and are sent only to your own servers over SSH.
MIT-licensed and local-first.
```

### 3b. Apple App Store description (same base, App-Store wording)

Use the Play text above with this head paragraph swapped in (Apple style,
mentions Face ID purpose + background task honesty):

```text
MyControlPanel is a pitch-black IT Control Center for macOS, Windows,
Linux, iOS, and Android. Connect over SSH and watch metrics, cronjobs,
apps, alerts, and logs refresh into one calm dashboard, with a terminal
and an AI assistant that already knows your fleet (bring your own key or
run Ollama locally). Face ID unlocks the app lock. Background refresh is
an explicit opt-in (~15 min, on-device only); alerts fire in the
foreground while the app is open.
```

Then keep the LIVE TODAY / HONESTLY LABELLED / PRIVACY blocks unchanged.

### 3c. Snap Store description

Use the Play full description verbatim, and append this confinement note
(do not list until the snap builds from CI — Beta.2 TM-2/TM-8 scope):

```text
Confinement: strict. Plugs: network (SSH + LAN agent reads). No daemons;
tray-mode scheduling uses per-user systemd units installed by script.
```

### 3d. Microsoft Store description

Use the Play full description verbatim, and append this capabilities note
(do not list until the MSIX builds from CI — same rule as snap):

```text
Per-user install only, no elevation, no admin. LAN client access for
agent reads. No background task declared while tray mode ships as Task
Scheduler scripts (Beta.2).
```

## 4. Keywords (Apple, ≤100 chars — 49 used)

```text
ssh,server monitor,homelab,cron,devops,uptime,sre
```

Play tags (store listing → tags): `ssh`, `server monitor`, `homelab`,
`devops`, `uptime`, `cron`, `sre`.

## 5. Privacy / support URLs (interim — repo-hosted until site launches)

| Purpose | URL |
|---|---|
| Support | https://github.com/alfirus/mycontrolpanel/issues |
| Privacy policy | https://github.com/alfirus/mycontrolpanel/blob/main/docs/store/privacy-permissions.md |
| Homepage | https://github.com/alfirus/mycontrolpanel |

Rule: swap all three to the launch site in the release PR that cuts the
first store build. Never ship a listing with a dead URL (link-check fails
the PR otherwise).

## 6. Permissions summary (must match code at release time)

- Android: `POST_NOTIFICATIONS` (runtime prompt on API 33+, requested when
  the background toggle flips on), `USE_BIOMETRIC` (app-lock only).
  Deliberately NOT declared: `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`,
  `RECEIVE_BOOT_COMPLETED`.
- iOS: `NSFaceIDUsageDescription` (biometric app lock); `BGTaskScheduler`
  periodic task only (identifier must equal the permitted identifier and
  the AppDelegate registration).
- Snap: strict, `network` plug; no daemons.
- Microsoft: private-network client; per-user install; no elevation.

Re-read the manifest / plist / entitlements in the release PR and paste
the file paths into the review — never answer from memory
(see `docs/store/privacy-permissions.md`).

## 7. What never appears in a listing

Prices, SLAs, "push notifications", "real-time streaming", GitHub / CI-CD /
Security as live features, background polling as built, or any testimonial
not collected from a real user. Full red lines in
`docs/store/ratings-answers.md`.

## 8. Release-readiness checklist (all boxes before any submit)

- [ ] `v*` tag cut; release artifacts attached (`release.yml`).
- [ ] Screenshots re-captured on the release commit
      (`docs/store/screenshot-checklist.md` — commit hash filled in).
- [ ] At least one real phone screenshot in the set (store rejection risk
      with desktop-only sets).
- [ ] Feature graphic 1024×500 (Play) + hero composition exported.
- [ ] 1–2 real user quotes collected, or the social-proof slot ships empty
      (never invented).
- [ ] Pricing sign-off recorded (Sofia + Finance) — until then only the
      Free/MIT line may be promised.
- [ ] In-ship honesty labels verified: AI BYO-key line, DEMO banners on
      GitHub/CI-CD/Security, background opt-in OFF by default + staleness
      line ("last checked Xm ago").
- [ ] Roadmap ↔ README sync confirmed for the release commit.

## Handoff

Messaging questions → Naura (CMO). Technical claims → via Sofia to
Maisarah's team. Pricing → Sofia + Finance. Visual assets → Hana
(card `t_c8b233d4`, builds on this kit). Sales execution → Syafiqah
(card `t_37226309`, kit in `docs/marketing/sales-kit-v1.md`).
