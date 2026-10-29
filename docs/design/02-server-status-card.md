# 02 — Server Status Card Redesign

Owner: Kira (UI/UX) · Status: spec for implementation (small) · Thresholds: PR #45 (`AppThresholds`)
Scope: `_serversSegment` (~L2079), demo card (~L2096), `_realServerBody` (~L717),
`MetricBar`/`StatusDot`/`Pill` in `lib/widgets/pitch_card.dart`

## 1. What is wrong today (before)

Reading the current card top-to-bottom, the visual hierarchy is:

1. `StatusDot` (8px pulsing dot) + server name + OS chip + status `Pill` — fine.
2. `ip • region • latency` in **9–11px `textMuted` (2.6:1)** — the line that answers
   *"is this box reachable and how slow?"* is the lowest-contrast line on the card.
3. Three `MetricBar`s (CPU / RAM / DISK) with **three different critical cutoffs at two
   call sites**: cpu crit > 0.75 (cyan otherwise), ram crit > 0.85 (blue otherwise),
   disk *warn* > 0.8 (grey otherwise). Same shape, three different semantics, and the
   demo card and `_realServerBody` each hardcode their own copies.
4. A 9-point `sparkline` strip (demo only) with no axis, no "last value" label, and no
   text alternative — color/shape-only information, invisible to screen readers
   (zero `Semantics` widgets anywhere in the app, verified by grep).
5. Live card footer: `LIVE • agent :9108 • up Nd` in 9px success-green — uptime, the
   number humans actually scan for, is the smallest text on the card.

So: the two most-scanned facts (reachability/latency, uptime) are the smallest and
dimmest; thresholds disagree between demo and live; the sparkline carries no accessible
name.

## 2. After — hierarchy spec

Card reading order, top to bottom (both demo and live variants):

1. **Header row (unchanged):** `StatusDot` + name + OS chip + status `Pill`.
   New rule: the `Pill` text is never the *only* carrier — it already isn't (dot + word).
2. **Reachability line (changed):** `ip • region • {latency}ms • up {N}d`, promoted to
   `textSecondary` 11px (`AppType.body`), latency value in `textPrimary` semibold.
   Rationale: one scan answers "which box, where, how slow, how stable". If
   `_useRealServers && latencyMs == 0`, today's `'no metrics yet'` copy stays — it is
   honest and already `textMuted`-free in practice after the 01-promotion.
3. **Metric bars (changed):** keep the three-bar row (it is compact and scans well),
   but all bars share `AppThresholds` (PR #45: cpu 0.75 / ram 0.85 / disk-warn 0.80,
   disk-crit 0.95) and all sub-threshold bars use one neutral track color instead of
   today's cyan/blue/grey split — hue must mean *state*, not *which metric*.
   Bar labels move to `textSecondary` per `01-design-tokens.md`.
4. **Trend strip (changed):** keep the sparkline, but add a trailing text label —
   `▲ 12ms p95` / `cpu p95 61%` — so the trend exists as text too, and wrap it in a
   `Semantics(label: 'CPU trend, peak 61 percent over 5 minutes')`. This closes the
   screen-reader gap without redesigning the strip.
5. **Live footer (changed):** `LIVE • agent :9108 • up Nd` grows to 11px and uptime
   becomes its own segment: `UPTIME 41d` in `textPrimary`, everything else stays muted.

Demo/live parity rule: demo card and `_realServerBody` must render the *same five
bands in the same order*. Today the live card drops the sparkline entirely and shows
a `No metrics agent` installer box instead — that box is correct content, but it
should sit *below* bands 1–2 (header + reachability), never replace them, so a
server without an agent still reads as a server.

## 3. Before / after sketch (textual, 360px width)

BEFORE:
```
● web-01            [OPERATIONAL]
  1.2.3.4 • eu • 42ms        <- 10px muted (2.6:1)
  CPU 71%  RAM 44%  DISK 63%  <- 3 hues, 3 cutoffs
  ~~~~sparkline~~~~           <- no label, no semantics
```

AFTER:
```
● web-01            [OPERATIONAL]
  1.2.3.4 • eu • 42ms • up 41d   <- 11px secondary, latency primary
  CPU 71%  RAM 44%  DISK 63%      <- one neutral hue, shared cutoffs
  ~~~~sparkline~~~~  cpu p95 74%  <- text label + Semantics
```

## 4. Implementation notes (for the small PR)

- Swap thresholds to `AppThresholds` at both call sites (~L723 demo, ~L2119 live).
  Pure constant swap, no layout change — safe without a device.
- Promote the two text colors (token swap only).
- Add the `Semantics` wrapper + trailing label on `_miniSparkline` callers.
- Do NOT reorder bands 1–5 in the same PR as the color swap; ship colors first,
  reorder second, so review can diff each behavior separately.

Accessibility acceptance: with TalkBack/VoiceOver on, a server card announces name,
status word, latency, uptime, and each bar as "CPU 71 percent, normal/warning/critical"
— never color alone.
