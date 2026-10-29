# 01 — Dark-Theme Design Tokens Audit

Owner: Kira (UI/UX) · Status: ratified spec · Implementation: PR #45 (`lib/theme/design_tokens.dart`)
Scope: `lib/theme/app_theme.dart`, `lib/widgets/pitch_card.dart`, all segments in `lib/screens/control_center_screen.dart`

## 1. Method

Counted every literal `BorderRadius.circular`, `EdgeInsets.all`, and `fontSize` in `lib/` on
`main` @ `003aed8`, then checked which foreground/background pairs actually carry meaning
against WCAG 2.2 contrast (computed, not eyeballed — script in task workspace).

## 2. Findings

### Colors — the ramp is good, the usage is not

| Token | Hex | Role today |
|---|---|---|
| `pitchBlack` | `000000` | scaffold, rail |
| `surface0` | `0A0A0A` | cards |
| `surface1` | `111111` | rows, selected nav |
| `surface2` | `1A1A1A` | chips, table headers |
| `border` / `borderLight` | `1E1E1E` / `262626` | hairlines |
| `textPrimary` | `FFFFFF` | headings |
| `textSecondary` | `8A8A8E` | body |
| `textMuted` | `52525B` | helper text, bar labels |
| `textDim` | `3F3F46` | timestamps |
| `accentCyan` | `00E5CC` | primary actions, live |
| `accentGreen` `accentAmber` `accentRed` `accentBlue` `accentPurple` | see `app_theme.dart` | legacy accents |
| `success` `warning` `critical` `info` | `00C950` `EAB308` `EF4444` `06B6D4` | status |

Measured contrast on real surfaces:

| Pair | Ratio | Verdict |
|---|---|---|
| Primary on surface0 | 19.8:1 | AAA |
| **Secondary on surface0** | **5.8:1** | **AA pass — the workhorse body color** |
| Muted on surface0 | 2.6:1 | FAIL even for large text |
| Dim on surface0 | 1.9:1 | FAIL — decorative only |
| Cyan on black | 13.1:1 | AAA |
| Critical on surface0 | 5.3:1 | AA pass |
| Warning / success on surface0 | 10.3 / 8.9:1 | AAA |
| Log body `E4E4E7` on `050505` | 16.1:1 | AAA |

**Before:** `textMuted` (2.6:1) is used for *meaningful* copy at 9–11px — the server
`ip • region • latency` line, `MetricBar` labels, card helper text. That copy is unreadable
for low-vision users and fails WCAG AA (4.5:1) outright.
**After (rule):** `textMuted`/`textDim` are decorative-only (timestamps, dividers-adjacent
captions, disabled chrome). Any text the user needs to act on is `textSecondary` or brighter.
Nurul: when implementing `docs/design/04`, promote the server meta line and `MetricBar`
labels to `textSecondary` — pure color-token swap, no layout change.

Two more color findings:
- **Two accent systems coexist** (`accentGreen #00FF88` vs `success #00C950`,
  `accentAmber #FFFFCC02`... vs `warning #EAB308`). Audit: `success/warning/critical/info`
  are the status path (Pills, dots); the `accent*` set is the brand path (cyan primary,
  blue RAM, purple cron). Rule: status meaning ⇒ `success/warning/critical/info` only.
  `accentRed/accentAmber` should be retired at the next touch of each call site.
- **Cyan-on-black filled buttons** (`INSTALL AGENT`, bottom-nav AI tile) pass at 13:1 —
  keep. But cyan is doing triple duty (brand + live + selected-nav). That is fine *because*
  each usage pairs cyan with a second cue (dot + label, icon + label). Never use cyan alone
  as the only carrier of state — see §4 of `02-server-status-card.md`.

### Type — a scale hiding inside ad-hoc sizes

`fontSize` counts: 10px ×152, 11px ×123, 12px ×77, 9px ×38, 13px ×27, 8px ×8.
That *is* a scale, just unnamed. Frozen as `AppType`:

| Token | Size | Intent |
|---|---|---|
| `caption` | 9 | log lines, badges, table cells |
| `body` | 11 | row titles, toggles, helper (the modal size) |
| `title` | 13 | primary row titles, card content |
| `heading` | 16 | card headers, screen titles |

Weights stay inline for now (w600–w800 + 0.3–0.8 tracking for eyebrows is consistent
everywhere it appears). Next step, not this PR: promote the `TextTheme` in
`AppTheme.dark` to reference `AppType` so `Theme.of(context).textTheme` stops drifting
from one-off `TextStyle`s.

### Spacing — 4pt grid, already ~there

`EdgeInsets.all` clusters on 12 ×28, 10 ×18, 8 ×9, 6 ×6, 16 ×4. Frozen as `AppSpacing`
(`xs 4 / sm 8 / md 12 / lg 16 / xl 20 / xxl 24`) plus `cardGap 12` and `sectionGap 16`.
Outliers (`all(7)`, `all(14)`, `all(20)`) are grandfathered — convert when the owning
card is next touched, do not churn.

### Radii — 10 values → 5

`BorderRadius.circular` counts: 8 ×99, 7 ×27, 12 ×22, 6 ×20, 10 ×18, 4 ×13, 16 ×5,
3/20/14 ×3 each. Frozen as `AppRadii` (`sm 6 / md 8 / lg 12 / xl 16 / pill 20`).
**Before:** `PitchCard` hardcoded `16` in three places while `cardTheme` hardcoded its
own `16` — two sources of truth for the same corner.
**After:** both reference `AppRadii.xlAll` (PR #45). Same pixels, one owner.

## 3. What PR #45 implements vs what stays spec

Implements (additive + 3-line wiring, zero visual change): `design_tokens.dart`,
`PitchCard` → tokens, `cardTheme` → `AppRadii.xlAll`.
Stays spec for Nurul/any frontend pass: muted→secondary promotion, accent-set
retirement, `TextTheme` ↔ `AppType` unification, outlier radii conversion.
