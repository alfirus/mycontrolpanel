# Store listings matrix — MyControlPanel

Status: draft for Sofia (voice) + Syafiqah (kit alignment) sign-off.
Nothing here is published until the release tag, re-captured screenshots,
and pricing sign-off exist (see `docs/sales-kit-review.md` launch blockers).
Voice: direct, technical, zero hype.

Copy source rule: `docs/store/listing-copy.md` is the SINGLE source for
all customer-facing wording — this matrix only maps those blocks into
per-store submission fields. Never fork the wording here; if a store
needs different words, change `listing-copy.md` first, then update the
field map below. (Deconfliction note: PR #142 reworked `listing-copy.md`
mid-flight; this file was revised to defer to it.)

Sources of truth: `docs/store/listing-copy.md` (copy),
`docs/store/privacy-permissions.md` (questionnaire answers),
`docs/store/ratings-answers.md` (age/content ratings),
`docs/store/screenshot-checklist.md` (capture freshness),
`docs/roadmap.md` + README matrix (live vs UI-ready),
`docs/sales-kit-review.md` (conditional-GO fixes — applied below).

## 1. Submission-field map

| Store | Title / name field | Value (from `listing-copy.md`) |
|---|---|---|
| Google Play | App name | MyControlPanel |
| Google Play | Short description (63/80) | Shared short, verbatim |
| Google Play | Full description (~780/4000) | Shared base, verbatim |
| App Store | App name (14/30) | MyControlPanel |
| App Store | Subtitle (25/30) | `Every server. One glance.` |
| App Store | Keywords (49/100) | `ssh,server monitor,homelab,cron,devops,uptime,sre` |
| App Store | Description (~780/4000) | Shared base, verbatim |
| Snap Store | Title + description | App name + shared base, verbatim, plus confinement note (strict, `network` plug, no daemons) |
| Microsoft Store | Title + description | App name + shared base, verbatim, plus capabilities note (per-user install, no elevation, no background task declared) |

Character counts were verified with `wc -m` in `listing-copy.md` —
re-verify there if any line changes; do not re-count here.

Price on all stores: Free, RM 0 (MIT-licensed, local-first). Never list
a paid tier until Sofia + Finance sign `docs/launch.md` pricing.

## 2. Categories

| Store | Category |
|---|---|
| Google Play | Tools (primary); Productivity (secondary) |
| Apple App Store | Utilities (primary); Productivity (secondary) |
| Snap Store | System / Utilities |
| Microsoft Store | Utilities |

## 3. Privacy / support URLs (interim — repo-hosted until site launches)

| Purpose | URL |
|---|---|
| Support | https://github.com/alfirus/mycontrolpanel/issues |
| Privacy policy | https://github.com/alfirus/mycontrolpanel/blob/main/docs/store/privacy-permissions.md |
| Homepage | https://github.com/alfirus/mycontrolpanel |

Rule: swap all three to the launch site in the release PR that cuts the
first store build. Never ship a listing with a dead URL (link-check fails
the PR otherwise). Support promise: "Community support on GitHub (MIT,
RM0). No SLA." — paid tiers are undecided, quote nothing.

## 4. Permissions snapshot (must match code at release time)

Summary only — the binding answers live in
`docs/store/privacy-permissions.md`:

- Android: `POST_NOTIFICATIONS` (runtime prompt, toggle-gated),
  `USE_BIOMETRIC` (app-lock only). NOT declared:
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `RECEIVE_BOOT_COMPLETED`.
- iOS: `NSFaceIDUsageDescription` (biometric app lock); `fetch` +
  `BGTaskScheduler` periodic task only.
- Snap: strict, `network` plug; no daemons.
- Microsoft: private-network client; per-user install; no elevation.

Re-read the manifest / plist / entitlements in the release PR and paste
the file paths into the review — never answer from memory.

## 5. What never appears in a listing

Binding list lives in `listing-copy.md` ("What never appears") and
`docs/store/ratings-answers.md` ("Red lines"): no prices, no SLAs, no
"push notifications" / "real-time streaming", no GitHub / CI-CD /
Security as live features, no tray-mode closed-app desktop alerts as
shipped, no invented testimonials.

## 6. Release-readiness checklist (all boxes before any submit)

- [ ] `v*` tag cut; release artifacts attached (`release.yml`).
- [ ] Screenshots re-captured on the release commit
      (`docs/store/screenshot-checklist.md` — commit hash filled in).
- [ ] At least one real phone screenshot in the set (store rejection risk
      with desktop-only sets).
- [ ] Feature graphic 1024×500 (Play) exported.
- [ ] Screenshot captions from `listing-copy.md` pasted per store
      (each under 120 chars).
- [ ] 1–2 real user quotes collected, or the social-proof slot ships empty
      (never invented).
- [ ] Pricing sign-off recorded (Sofia + Finance) — until then only the
      Free/MIT line may be promised.
- [ ] In-ship honesty labels verified: AI BYO-key line, DEMO banners on
      GitHub/CI-CD/Security, background opt-in OFF by default + staleness
      line ("last checked …" — never silent).
- [ ] Roadmap ↔ README sync confirmed for the release commit.
- [ ] Alya security review on the release PR (privacy disclosures).

## Handoff

Messaging questions → Naura (CMO). Technical claims → via Sofia to
Maisarah's team. Pricing → Sofia + Finance. Visual assets → Hana
(card `t_c8b233d4`, builds on this kit). Sales execution → Syafiqah
(card `t_37226309`, kit in `docs/marketing/sales-kit-v1.md`).
