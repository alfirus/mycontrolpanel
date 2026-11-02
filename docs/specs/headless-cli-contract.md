# Headless CLI contract (TM-1 freeze — Lina, 2026-11-02)

Frozen by 2026-11-21 per `docs/project/tray-mode-plan.md` risk 2: changes
after freeze need Rina sign-off + same-day notice to Zara / Elizabeth /
Lisa. The machine-readable half of this freeze lives in
`test/headless_contract_test.dart` — a failing contract test means the
freeze moved, not that the test is stale.

Architecture rationale: `docs/decisions/004-headless-cli-architecture.md`.
Security boundary: `docs/decisions/003-tray-headless-security.md` (binding,
unchanged).

## 1. Entry-point

- Scheduler argv (exact): `mycontrolpanel[.exe] --poll-headless`.
  No subcommand, no extra args. The adapter self-scans argv via
  `HeadlessSecurity.findSecretMaterialInArgs` and exits `1` on any
  violation (tampered-artifact fail-loud).
- `main(List<String> args)` checks the flag FIRST, before any plugin init
  or `runApp`. Flag present → one tick, print JSON, `exit(code)`. No
  window ever boots on this path. Flag absent → normal launch, untouched.
- `dart run my_control_panel:headless_check --self-test` is the CI/dev
  harness (fake transport, temp state dir). It is NOT a scheduler target.

## 2. Exit codes

| Code | Meaning | When |
|---|---|---|
| `0` | tick ok | evaluated (alerts notified or nothing fresh) |
| `2` | tick skipped | consent OFF / vault locked / backoff active / lock held by another tick / no host answered on a skipped path |
| `1` | error | tainted argv / total transport failure / pre-evaluation crash |

## 3. Stdout (machine-readable JSON, one line)

```json
{
  "version": 1,
  "status": "notified",
  "exitCode": 0,
  "checkedAtMs": 1730600000000,
  "freshTitles": ["Disk 82% full on / (web)"],
  "notification": {"title": "MyControlPanel alert", "body": "Disk 82% full on / (web)"},
  "reason": "only on skipped/error"
}
```

- `status`: `ok` | `notified` | `skipped` | `error`.
- Titles only — never credentials, markers, or paths (pinned by test).
- Empty body + `status: ok` means "steady state, nothing fresh".

## 4. State file (`headless_state.json`, schema version 1)

```json
{
  "version": 1,
  "lastCheckMs": 1730600000000,
  "seenKeys": ["alert::web::Disk 82% full on /"],
  "lastSentMs": {"alert::web::Disk 82% full on /": 1730600000000},
  "consecutiveFailures": 0
}
```

- Locations (per-user only, ADR-003): Windows
  `%LOCALAPPDATA%\MyControlPanel\`; Linux `$XDG_CONFIG_HOME/mycontrolpanel`
  (fallback `~/.config/mycontrolpanel`); macOS
  `~/Library/Application Support/MyControlPanel/`. `$MCP_STATE_DIR`
  overrides (CI/tests only — a path, never secret material).
- `seenKeys` uses `kind::owner::title` verbatim with `AlertWatch`
  (parity test). Replaced each tick (resolve→re-fire notifies again).
- `lastSentMs` enforces the 6 h resend cooldown (flap suppression).
- `consecutiveFailures` persists the `PollPolicy` streak across restarts.
- Single-flight: `headless.lock` (exclusive, 10 s acquisition timeout) —
  a contended tick exits `2`, never overlaps.
- The shared prefs stamp `background_alerts_last_check_ms` is written on
  EVERY tick (including skips/errors) so "last checked Xm ago" stays
  honest with the window closed.

## 5. Reuse table (verbatim, never reimplemented)

| Concern | Source | Frozen values |
|---|---|---|
| Gate + exit codes | `HeadlessSecurity` | consent-first, vault-second |
| Poll backoff | `PollPolicy` | base 5 min → cap 1 h |
| Disk verdicts | `AlertRules` | warn ≥ 80 %, crit ≥ 90 % |
| Gauge thresholds | `Thresholds` | warn 0.85 / crit 0.95 |
| Payload | `NotificationHook.build` | `{title, body}`, max 3 + "…and N more", title `'MyControlPanel alert'` |
| Dedup identity | `AlertWatch.keyFor` | `kind::owner::title` |
| Consent pref | `BackgroundAlerts` | `background_alerts`, default OFF |
| Transport shape | `pollHostAlerts` | agent-HTTP + SSH union, 15 s/host, max 10 hosts |

## 6. Adapter rules (production fetch path)

- Load servers RAW via `SecureStore.readRawServerListJson` (decode only).
  NEVER `SecureStore.readServers()` headless — it heals plaintext into the
  keychain (interactive-only). Option A: the prefs key is named only in
  `SecureStore` (pinned by `secure_prefs_guard_test`).
- Resolve each marker read-only: one `SecureStore.readSecret` per
  `secure:` host (+ agent token). Non-`secure:` markers and null/empty
  secrets skip the host.
- App-lock (`biometrics` pref ON) ⇒ vault treated as locked ⇒ exit `2`,
  no biometric prompt.
- Per-host failures are swallowed (one sick host never sinks the run);
  total failure ⇒ exit `1` + streak increment.
- CI failed runs: accepted by the pipeline as `kind: 'ci'` signals but
  NOT yet fed by the adapter (extension point for Elizabeth/Lisa —
  map into `HeadlessSignal`, keep the `CI failed: …` display format).

## 7. Scheduler template invariants (Alya reviews)

Per-user scope, no elevation, exact `--poll-headless` argv, no
`Environment=`/stored secrets, mode `0600` file artifacts where files
are used. Templates: `scripts/headless/{windows,linux,macos}/`.
Manual install/uninstall scripts sit beside them (dogfood path);
the managed lifecycle (verify/status/ledger) is Zara's (t_13eee02b)
and must not re-template argv.
