# 03 — Navigation / IA Pass

Owner: Kira (UI/UX) · Status: spec (no code in this pass — needs Lina/product call on grouping)
Scope: `_buildSideRail` (~L1862), `_buildBottomNav` (~L1975), `_buildContent` (~L1984),
`_overviewCompact` (~L2026), in `lib/screens/control_center_screen.dart`

## 1. Inventory (actual, `main` @ `003aed8`)

The rail holds **13 destinations**, indices 0–12:

| # | Destination | Accent | Bottom nav? |
|---|---|---|---|
| 0 | Overview | cyan | yes |
| 1 | Servers | blue | yes |
| 2 | Cronjobs | purple | no |
| 3 | Apps | green | no |
| 4 | GitHub | white | yes |
| 5 | GitLab | purple | no |
| 6 | Alerts | warning | no (bell icon in app bar only) |
| 7 | Deploys | cyan | yes (labelled rocket) |
| 8 | Logs | grey | no |
| 9 | Metrics | green | no |
| 10 | Security | red | no |
| 11 | Settings | grey | yes |
| 12 | Terminal | cyan | no (opens full-screen replace) |

## 2. Findings

**F1 — Two adjacent purple icons mean different things.** Cronjobs (#2) and GitLab (#5)
share `accentPurple` but are unrelated domains. Worse, Apps (#3) and Metrics (#9) share
green, and Logs (#8) and Settings (#11) share grey. Accent-per-destination currently
encodes nothing; it reads as decoration. Rule: one accent per *group* (see §3), never
per item, or drop per-item accents entirely and reserve color for selection state.

**F2 — Terminal and Logs share the same glyph.** Both rail items use
`Icons.terminal_outlined` (#8 Logs, #12 Terminal). At a glance they are
indistinguishable. Terminal should keep the terminal glyph; Logs should move to
`Icons.article_outlined` / `receipt_long_outlined` (a *document*, which is what a log is).

**F3 — Bottom nav is a different app from the rail.** Mobile gets Overview / Servers /
GitHub / Deploys / Settings + AI button. Six destinations (Cronjobs, Apps, Alerts,
Metrics, Security, Logs) plus GitLab and Terminal are reachable only via... nothing on
mobile — there is no drawer on desktop-width only (`drawer:` is null on desktop, bottom
nav replaces it on mobile, and the rail is the drawer). Concretely: on a phone, Alerts
(#6) is reachable only through the app-bar bell, and Cronjobs/Apps/Metrics/Security
have no path at all except Overview's compact cards. The IA must be consistent across
form factors, not two different products.

**F4 — GitHub and GitLab are siblings but not adjacent in practice.** They are adjacent
in the rail (#4/#5 — good) but GitHub is in the bottom nav while GitLab is
mobile-unreachable (bad). Either both VCS surfaces collapse under one destination or
both must be in the mobile set.

**F5 — Overview duplicates everything.** `_overviewCompact` renders all 11 cards stacked
(mobile) or paired (desktop). That is correct as a dashboard — but it means every new
destination auto-appears twice (overview + full view) with `compact` flag drift between
the two renderings. Rule going forward: the full view is the source of truth; the
compact card is the same widget with `compact: true`, never a fork.

**F6 — Index 12 (Terminal) is a mode, not a destination.** It replaces the whole
scaffold body including nav chrome. Users lose their place. It should be a pushed route
(`Navigator.push`) with a back affordance, not a nav index — today `_navIndex = 12`
breaks "selected" semantics (nothing in the rail corresponds to where you are).

## 3. Proposed IA (needs Lina sign-off before code)

```
Observe            Manage              Respond             Configure
Overview           Servers             Alerts (!)          Settings
Metrics            Apps                Deploys
Logs               Cronjobs            AI Chat (drawer)
Security           GitHub / GitLab*    Terminal (route)
```

- Rail groups with 12px group labels (`OBSERVE / MANAGE / RESPOND / CONFIGURE`),
  dividers between groups. 13 items × ~36px still fits a 640px-tall rail with the
  Quick-Stats card intact.
- `*` GitHub/GitLab: preferred option is **one "Source" destination with two tabs**
  (the tab pattern already exists in `_githubSegment`'s Issues/PRs/Tasks toggle), which
  also fixes F4 on mobile. Fallback: keep both, but both enter the mobile set.
- Bottom nav (mobile, 5 slots + AI): Overview / Servers / Alerts (!) / Deploys /
  Settings. Alerts replaces GitHub: firing incidents outrank VCS on a phone, and the
  app-bar bell already admits alerts are global. GitHub/GitLab live under Overview
  cards + a "More" sheet for the rest. The `!` badge on Alerts shows the firing count
  (`_alertBadge` exists but is never displayed — wire it here).
- Terminal becomes a pushed route with proper back; index 12 disappears.
- Icon fixes ship immediately (no product call needed): Logs glyph change, dedupe the
  purple/green/grey accent collisions per F1.

## 4. Smallest shippable steps (ordered)

1. Glyph + accent dedupe (F1, F2) — 10-line diff, no behavior change.
2. Surface `_alertBadge` on the app-bar bell + bottom nav (F3 partial).
3. Group labels in rail (F3) + Terminal-as-route (F6).
4. GitHub/GitLab merge decision (F4) — product call, then implement.
