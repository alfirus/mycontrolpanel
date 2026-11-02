# ADR-005: Headless CLI architecture + TM-1 frozen contract

Status: **accepted** — Lina (tech lead / TM-1 owner), 2026-11-02.
Binding on TM-2/TM-3 (Zara, Elizabeth), TM-5 (Farah), TM-6 (Balqis).
Companions: `docs/specs/headless-cli-contract.md` (machine-readable
freeze), `docs/decisions/003-tray-headless-security.md` (security
boundary — unchanged, referenced, not reopened).

## Context

Rina's tray-mode plan (`docs/project/tray-mode-plan.md`, TM-1) and
`docs/design/05-background-alerting.md` §8.1 sketch the headless entry-point
as "e.g. `mycontrolpanel --poll-headless`" with a suggested exit-code
table, and name Lina as the decision owner with a 2026-11-21 freeze. Three
downstream cards build against this contract in parallel (Zara's scheduler
lifecycle + run ledger, Elizabeth's closed-app slice + tray, Lisa's
`bin/mcpoll.dart` + agent snapshot endpoint) — so the freeze must settle
naming, file ownership, and the exact reuse table NOW, not incrementally.

Alya's ADR-003 already froze the security boundary (vault-only reads,
no plaintext fallback, per-user artifacts, consent gating, exit codes).
This ADR does not reopen it: it places the CLI architecture inside it.

## Decision

**One headless poll pipeline, three layers:**

1. **Pure core — `lib/background/headless_check.dart` + `lib/background/headless_state.dart`.**
   Pure Dart (`dart:async`/`dart:io`/`dart:convert` + pure lib modules
   only). Owns the gate (via `HeadlessSecurity`), the backoff (via
   `PollPolicy`, streak persisted in state), the verdicts (via `AlertRules`
   defaults 80/90%), and the payload (`NotificationHook.build` verbatim,
   title `'MyControlPanel alert'`). Transition-only notify against a
   persisted seen-set; single-flight via an exclusive lock file; stdout is
   versioned JSON carrying titles only. Transport is an injected
   `fetchAll()` callback — this layer never touches network, vault, prefs,
   or plugins, so `dart run my_control_panel:headless_check` (CI harness,
   `bin/`) and the shipped binary share it verbatim.

2. **Flutter adapter — `lib/headless.dart`, entered from `main()` before
   any UI boots.** When `--poll-headless` is present: read prefs once
   (consent + app-lock), load servers RAW from prefs (decoded, never via
   `SecureStore.readServers()` — that method heals plaintext into the
   keychain and healing is interactive-only per ADR-003), resolve each
   `secure:` marker with one read-only `SecureStore.readSecret`, poll
   short-lived agent/SSH legs (15 s timeout, max 10 hosts — parity with
   `BackgroundAlerts.runBackgroundTick`), deliver via
   `DesktopAlerts.showFreshPayload`, stamp
   `DesktopAlerts.recordCheck()` on EVERY tick including skips/errors (T3),
   print JSON, `exit(code)`. No `runApp`, no window, no biometric prompt.
3. **Scheduler artifacts — `scripts/headless/` templates + minimal manual
   install/uninstall scripts per OS.** Exact argv
   `mycontrolpanel[.exe] --poll-headless`, per-user scope, no elevation,
   validated by `HeadlessSecurity.validateSchedulerArtifact` (pinned in
   `test/headless_contract_test.dart`).

Frozen contract details (flag, exit codes `0/2/1`, stdout/state schemas,
paths, reuse table): `docs/specs/headless-cli-contract.md`. Manual
install/uninstall: `docs/runbooks/headless-manual-install.md`.

## Alternatives considered

- **Shipped target as a `dart run` CLI (`bin/mcpoll`-style).** Rejected
  for the scheduler path: pure Dart cannot read the OS vault or the
  app's prefs plugins, so a standalone script would need a second
  credential store — a new secret boundary Alya would have to review.
  The installed app binary already links the vault; the flag reuses it.
  (`bin/headless_check.dart` exists but is explicitly a fake-transport
  CI/dev harness, not a scheduler target.)
- **Second prefs (headless-specific consent / seen-set).** Rejected:
  §8.2 invariants require the SHARED `background_alerts` pref and the
  SHARED last-seen identity so in-app and headless rails never
  double-toast. The state file extends — never duplicates — the prefs
  stamp.
- **Healing/migration in the headless tick.** Rejected (ADR-003): any
  keychain write without a user present risks locking the user out
  silently. Plaintext hosts are skipped; the UI's SecurityPosture
  finding stays the re-entry path.

## Consequences

- Downstream file boundaries (no two cards own the same file):
  - Lina: `lib/background/*`, `lib/headless.dart`, `lib/main.dart` gate,
    `bin/headless_check.dart`, `scripts/headless/*`,
    `test/headless_*_test.dart`, `.github/workflows/headless.yml`,
    `docs/decisions/004-*`, `docs/specs/headless-cli-contract.md`,
    `docs/runbooks/headless-manual-install.md`, plus additive
    `DesktopAlerts.showFreshPayload` (foreground-owned file — Lina's
    change is additive-only, no behavior change).
  - Zara (t_13eee02b): lifecycle/verify/status/ledger + ops runbook on
    top of these templates; must not re-template argv.
  - Elizabeth (t_a0fe4895): slice integration, tray shell, launchd scope;
    reuses the core, does not fork it.
  - Lisa (t_aaebf4e9): `bin/mcpoll.dart` real-fetch CLI + agent snapshot
    endpoint; maps into `HeadlessSignal`, does not redefine the payload.
- Contract churn after 2026-11-21 needs Rina sign-off + same-day
  downstream notice (plan §risk 2).
- Privacy: no new retained state beyond the state file (seen-keys +
  last-check) — covered by `docs/specs/tray-headless-privacy.md`, no
  update needed.
