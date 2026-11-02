# Headless slice verdict parity (Elizabeth)

Closed-app vertical slice: **headless verdicts == in-app verdicts**,
including stale and no-data cases. This page is the human-readable half
of the parity proof; the machine-readable half is
`test/headless_slice_test.dart` (shared fixtures diffed on both rails —
a failing parity test means the rails drifted, not that the test is
stale).

Companions: `docs/specs/headless-cli-contract.md` (frozen exit codes +
stdout schema — unchanged by this slice), Kira's
`docs/design/06-alert-tray-ux.md` §4 (grouping/dedup/exactly-once).

## What "verdict" means

One evaluated input set — firing `AlertEntry`s + CI `DeployItem`s —
produces one verdict: the key set + fresh-title strings announced on a
rail. Both rails evaluate with the same frozen table
(`AlertRules` 80/90, `Thresholds` 0.85/0.95, `PollPolicy` 5 min → 1 h,
`NotificationHook.build` verbatim, 6 h resend cooldown, seen-set
REPLACED each tick).

| Case | In-app rail | Headless rail | Parity |
|---|---|---|---|
| Firing alert + failed run | `AlertWatch.currentKeys` / `freshTitles` → badge + snack + OS toast | `signalsFromAlerts` + `HeadlessSlice.signalsFromCiRuns` → JSON + OS toast | Identical keys (`kind::owner::title`) + identical strings (`'X (server)'`, `'CI failed: app ver'`) |
| Resolved alert / passing run | Key leaves the set, row clears | Key leaves the set, no notify | Identical |
| Steady firing (no change) | Seen → silent | Seen → `ok`, silent | Identical (both replace the seen-set) |
| Resolve → re-fire | Fresh again → toasts | Fresh again → `notified` | Identical |
| No-data (hosts answered, nothing firing) | Badge 0, no toast, staleness stamped | `ok`, silent, staleness stamped (`recordCheck` every tick incl. skips/errors) | Identical |
| CI leg sick | Timeline keeps last-good cache, no toast | CI contributes nothing, host tick proceeds | Identical (sickness is contained per-leg on both) |
| Backoff active | `AlertPollJob` delays the next tick | Tick skips, exit 2 | Identical intent (skip-don't-retry, T6) |
| Consent OFF / vault locked | No background work; guarded reads | Tick skips, exit 2, touches nothing | Identical (ADR-003) |
| No servers configured | Empty state, badge 0 | Exit 1 (`no host answered` → total-transport-failure path) | **Documented divergence** — the scheduler runbook requires ≥1 server before install; a scheduled tick with nothing to poll fails loudly instead of reporting a false `ok`. Frozen contract, not slice scope. |
| Blank producer titles (degenerate) | `currentKeys` keeps them (foreground quirk) | Both headless mappings drop them (stdout hygiene) | **Documented divergence** — unreachable in practice (producers always set titles); foreground-owned, not slice scope. |

## CI half (new in this slice)

Before this slice the headless tick evaluated alerts only, so a failed
CI run toasted in-app but never headless. The adapter
(`lib/headless.dart`) now enriches every host tick with failed runs:

- Seam: `fetchRuns` (injectable; tests drive it with fakes).
- Production default: tracked `github_repos` + `gitlab_projects` from
  the same prefs keys the control center reads; tokens from the vault
  **read-only** (`github_token` / `gitlab_token` via the injected
  `readVault`, else `SecureStore.readSecret`); GitHub via
  `CiSyncService` (per-repo backoff + last-good cache, never throws),
  GitLab via per-project `projectPipelines` (try/catch each).
- Mapping: `HeadlessSlice.signalsFromCiRuns` — failed only, key
  `ci::<env>::<app> <version>`, line `CI failed: <app> <version>`,
  verbatim with `AlertWatch`.
- Safety: no token ⇒ that VCS skips silently; CI throw ⇒ host tick
  proceeds; `answered` stays host-driven (frozen exit semantics —
  CI enrichment never flips an exit code by itself).

## Non-goals (explicit)

- No payload/argv/contract change: flag, exit codes, stdout schema and
  the TM-1 freeze are untouched (Lina owns; changes need Rina sign-off).
- No scheduler artifacts: `scripts/headless/*` stays Lina's; lifecycle
  on top is Zara's (`t_13eee02b`).
- No Settings/consent UI: Nurul's lane stays untouched.
