# Screenshot checklist — store + release freshness

Rule (from `docs/release-gate.md` docs bar): README screenshots match the
current UI at every `v*` tag. Store listings reuse the same set — never
mockups, never stale UI.

## Required captures (re-take when the UI changes)

- [ ] `docs/screenshots/overview.png` — Overview grid, ~1600×1000, with at
      least one connected server (no demo-only grid for release).
- [ ] `docs/screenshots/server-details.png` — Server Details 3-column layout
      on desktop (Connection, Live Metrics, Alerts, Apps, Cronjobs).
- [ ] `assets/marketing/hero.png` — hero composition for launch page.
- [ ] `assets/marketing/hero-laptop.png` + `hero-phone.png` — lifestyle pair.
- [ ] Phone capture — one real Android/iOS screenshot proving the mobile
      layout (store listings reject desktop-only sets).

## Per-store counts (minimum viable)

- Google Play: ≥2 phone screenshots + 1 feature graphic (1024×500).
- App Store: 6.5" + 5.5" iPhone sets (or one set + scaling note); iPad if
  tablet layout claimed.
- Snap / Microsoft: 1 desktop screenshot each (Overview preferred).

## Freshness procedure (each capture)

1. `flutter run -d <target>` on the release candidate commit.
2. Connect a real server (SSH + `:9108` agent) so LIVE banners show.
3. Capture, overwrite the file in place, note the commit hash below.
4. Tick the README docs-bar box only after all files above are re-captured.

Last captured against commit: ____ (fill at release time; empty means stale).
