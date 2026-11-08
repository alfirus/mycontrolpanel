# Store-ready visual pack v1 — manifest (Hana)

Owner: Hana (Visual Content Designer) · Reports to Naura (CMO).
Brand review: Kira (dotted line) — PENDING sign-off.
Messaging sign-off: Naura — SIGNED 2026-11-03 (re-review t_9c86034a, post-#160).
Image pipeline: deterministic PIL renders from `lib/theme` tokens
(series-conditioned on `_reference-render-1600x1000.png`).
The `image-generation` skill (Muse pipeline) is not installed on this
worker profile, so no Muse calls were made; the quality bar below is the
test: every headline legible, series consistent, honesty labels burned in.

## 1. Brand rationale

- Tokens: `pitchBlack #000000`, `surface0 #0A0A0A`, `border #1E1E1E`,
  `textPrimary #FFFFFF`, `textSecondary #8A8A8E`, `accentCyan #00E5CC`;
  status meaning uses `success #00C950` / `warning #EAB308` /
  `critical #EF4444` / `info #06B6D4` ONLY (never the brand `accent*`
  set) per `docs/design/01-design-tokens.md` and Kira's
  `lib/theme/alert_tokens.dart` (AA ≥ 4.5:1 on `surface0`).
- Logo/wordmark: canonical `assets/icon/app_icon.png` composited into
  renders (Penpot brand-kit export; Penpot at `localhost:9001` reachable
  but requires interactive auth, so no direct API pull from headless CI).
- Type: bold sans headlines (white), regular sans body (`textSecondary`),
  cyan kicker `IT CONTROL CENTER`; footer trust line on every render:
  `MIT · No account · No tracking · Credentials stay in your OS keychain`.
- Series conditioning: `_reference-render-1600x1000.png` locks card
  radius/border, KPI strip, bar style, footer; all 10 shippables derive
  from it — no per-image palette drift.
- Beats the `docs/infographics/` HTML pipeline as quality bar: real type
  (selectable in PDF), exact store dimensions, linted in CI
  (`tool/check_store_assets.dart` + `store-visuals.yml`).

## 2. Files (10 shippable + 1 reference)

| File | Size | Purpose | Caption (from `listing-copy.md`, ≤120 chars) |
|---|---|---|---|
| `assets/store/feature-graphic-1024x500.png` | 1024×500 | Play feature graphic | Every server. One glance. |
| `assets/store/hero-feature-graphic-1600x900.png` | 1600×900 | Launch/hero 16:9 | Every server on one pitch-black screen — live metrics over SSH. |
| `assets/store/phone-01-dashboard-dark-1080x1920.png` | 1080×1920 | Overview grid (dark) | Every server on one pitch-black screen — live metrics over SSH. |
| `assets/store/phone-02-dashboard-light-1080x1920.png` | 1080×1920 | Overview grid (light) | Drill into any server: metrics, alerts, apps, cronjobs, logs. |
| `assets/store/phone-03-metrics-1080x1920.png` | 1080×1920 | Metrics + p95 | Live metrics via a one-click stdlib-only agent. |
| `assets/store/phone-04-alerts-consent-stale-1080x1920.png` | 1080×1920 | Alerts + consent + stale | Firing signals with honest staleness — background opt-in, default OFF. |
| `assets/store/phone-05-logs-terminal-1080x1920.png` | 1080×1920 | Log tail + terminal | Built-in SSH terminal next to the dashboard — no tab-hopping. |
| `assets/store/phone-06-settings-lock-1080x1920.png` | 1080×1920 | Settings + app lock | Credentials stay in your OS keychain. Background opt-in, OFF by default. |
| `assets/store/desktop-07-tray-1600x1000.png` | 1600×1000 | Tray preview (Beta.2 plan) | Tray preview — Beta.2 plan, not shipped as closed-app delivery. |
| `assets/store/desktop-08-notification-1600x1000.png` | 1600×1000 | Notification + actions | Firing signals find you first — while the app is open. |
| `assets/store/_reference-render-1600x1000.png` | 1600×1000 | Series conditioner (not for stores) | — |

## 3. Honesty labels burned into pixels

- `phone-01/02/05`, `desktop-07`: `GitHub / CI-CD / Security: DEMO —
  wiring on roadmap`.
- `phone-03`: `Not a Grafana replacement — no retention/export yet`;
  refresh is `manual rescan / tab switch`, never "streaming".
- `phone-04/06`: background `default OFF`, `~15 min`, `no push relay`,
  `Last checked … — never silent`, `iOS may deliver hours apart`.
- `desktop-07/08`: tray is a `Beta.2 plan, NOT shipped as closed-app
  delivery`; notification copy per Kira `AlertCopy` (≤48/≤140 chars).
- Nothing promises prices, SLAs, push delivery, real-time streaming, or
  testimonials (none collected — slot ships empty per Naura's matrix).

## 4. Freshness + re-capture rule

Synthetic series-conditioned renders, generated on the merge commit of
this pack. Per `docs/store/screenshot-checklist.md` they MUST be
re-captured from the release-candidate commit with a real connected
server (LIVE banners) before any store submit; record the commit hash in
the checklist at that time. Until then the checklist stays unticked.

## 5. Sign-offs (fill before store submit)

- [ ] Kira brand review (tokens, series consistency, legibility)
- [x] Naura messaging sign-off (claims vs README matrix + `listing-copy.md`) — GRANTED 2026-11-03, re-review t_9c86034a post-#160 (pixels vision-verified on main).
- [ ] Sofia voice · Syafiqah kit safety (companions, not blocking this pack)
- [ ] Alya privacy review on release PR (permissions/nutrition answers)

## Handoff

Messaging → Naura. Engineering/claims → via Sofia to Maisarah's team.
Sales execution → Syafiqah (`docs/marketing/sales-kit-v1.md`).
Store fields → `docs/store/`. One-pager → `docs/sales-kit/one-pager.pdf`.
