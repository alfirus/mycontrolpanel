# 04 — Empty / Loading / Error States (Nurul: implementation spec)

Owner: Kira (UI/UX) · Status: build-ready spec · Implementer: Nurul (Frontend)
Scope: GitHub (`_githubSegment` ~L2400, `_realGithubCard` ~L2442), Deploys/CI-CD
(`_deploysSegment` ~L2775), Logs (`_logsSegment` ~L2872), AI chat (`_buildChatDrawer` ~L3020).
MOCK views = unconfigured/demo fallbacks (`mockServers`, `mockIssues`, `mockLogs` …).

## 1. The one pattern: `StateView`

Build **one** shared widget, use it in all four surfaces. No bespoke per-screen
empty boxes after this.

```dart
enum PanelState { data, loading, empty, error }

class StateView extends StatelessWidget {
  final PanelState state;
  final IconData icon;        // empty/error iconography (see table)
  final String headline;      // 13px w700 primary — what is true
  final String body;          // 11px secondary — why + what to do
  final String? actionLabel;  // e.g. 'OPEN SETTINGS', 'RETRY'
  final VoidCallback? onAction;
  final bool compact;         // pass through from the segment
}
```

Behavior rules:
- `loading`: 14px `CircularProgressIndicator` (accentCyan) + `Semantics(label:
  'Loading …', liveRegion)` — the codebase already shows bare spinners in the
  GitHub trailing row and log refresh; centralise, and always pair with a text label.
- `empty`: icon + headline + body + optional action. Min touch target on the action:
  48×48 (`FilledButton`, never bare `InkWell` text — see §3).
- `error`: same frame, `warning`-colored icon, body = first line of the error
  (the segments already do `e.toString().split('\n').first` — keep that), action is
  always `RETRY` wired to the existing poll (`_pollGithub`, `_pollRealLogs`, …).
- DEMO-vs-EMPTY distinction (the honest-data rule): an unconfigured surface
  (`!_ghConfigured`, no saved servers) is **not** an error and **not** empty-data —
  it is `empty` with the headline `NOT CONNECTED` and the action `OPEN SETTINGS`.
  Never render demo/mock rows without the `• DEMO` title suffix the cards already
  carry — silent fake data is the one thing this app must not do.

## 2. Per-surface copy (use verbatim)

| Surface | State | Headline | Body | Action |
|---|---|---|---|---|
| GitHub, unconfigured | empty | `GITHUB NOT CONNECTED` | `Add a token in Settings to go live. Showing sample issues until then.` | `OPEN SETTINGS` → `_goTo(11)` |
| GitHub, live, zero items | empty | `QUEUE IS CLEAR` | `No open {issues/PRs/tasks} across N repos.` (keep today's ✓ affordance) | none |
| GitHub, live, failure | error | `GITHUB SYNC FAILED` | first error line | `RETRY` → `_pollGithub` |
| Deploys (CI/CD), no runs | empty | `NO RUNS YET` | `Push to a tracked repo or check the Actions tab on GitHub.` | none / `VIEW REPO` if URL known |
| Deploys, failure | error | `DEPLOY HISTORY UNAVAILABLE` | first error line | `RETRY` |
| Logs, no servers | empty | `NO SERVERS` | `Add servers in Settings for real SSH logs.` (demo stream keeps `• DEMO` title) | `OPEN SETTINGS` |
| Logs, filter matches nothing | empty | `NO LINES MATCH` | `No {LEVEL} lines in the last N fetched. Try ALL.` | `SHOW ALL` → reset `_logFilter` |
| Logs, SSH failure | error | `LOG TAIL FAILED` | first error line (host + source: `journal/syslog/docker`) | `RETRY` → `_pollRealLogs` |
| AI chat, no provider | empty | `NO AI PROVIDER` | `Configure a provider to make the assistant control-center aware.` | `CONFIGURE` (existing button stays) |
| AI chat, request failure | error | inline bubble | error text as today's assistant bubble + | `RETRY` chip under the bubble |

## 3. Accessibility acceptance (applies to all four)

1. **Names, not colors.** Every state icon gets `semanticLabel`
   (`'No data'`, `'Sync failed'`, …). Today there are zero `Semantics` in the app —
   this spec is where that ends for these four surfaces.
2. **Live regions.** Loading → `Semantics(liveRegion: true)` announces start/end;
   error arrival announces via the same region. Chat already streams text — new error
   bubbles must announce, not just appear.
3. **Touch targets.** Replace bare `InkWell` text CTAs (`SYNC`, `VIEW ALL →`,
   `REFRESH →`) with real `TextButton`/`FilledButton` (48px min) when touching these
   rows. Grandfather untouched rows; convert rows this spec touches.
4. **Contrast.** State body copy is `textSecondary` 11px minimum (5.8:1, AA) —
   never `textMuted` (2.6:1, fails) — per `01-design-tokens.md` §2.
5. **Reduced motion.** The pulsing `StatusDot` and any spinner must respect
   `MediaQuery.disableAnimations`: pulse halo off, spinner becomes static
   `refresh` icon + `SYNCING…` text. One-line check at each site.

## 4. Out of scope

- Restructuring the segments themselves (that's `03-navigation-ia.md` step order).
- The `No metrics agent` installer box: correct content, moves under bands 1–2 per
  `02-server-status-card.md` when that ships — do not restyle it here.

## 5. Definition of done for Nurul's PR

- [ ] `StateView` added to `lib/widgets/` and used in all four surfaces above.
- [ ] Copy matches §2 verbatim (i18n comes later; one source of copy now).
- [ ] `flutter analyze` clean, `flutter test` green (CI runs the test gate on every PR).
- [ ] Manual pass with screen reader on each of the 10 rows in §2's table.
