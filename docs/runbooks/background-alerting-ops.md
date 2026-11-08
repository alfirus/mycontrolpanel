# Background alerting — ops runbook (Zara, TM-2)

How to install, verify, monitor, and remove the OS-scheduled headless
poll that powers closed-app alerts. Companion pages:

- Manual (unmanaged) scheduler path:
  `docs/runbooks/headless-manual-install.md` (Lina)
- Frozen tick contract: `docs/specs/headless-cli-contract.md` (Lina)
- Security boundary: `docs/decisions/003-tray-headless-security.md`
- Architecture: `docs/decisions/005-headless-cli-architecture.md`

## 1. What the managed scheduler runs

The OS task/timer does NOT fire the app binary directly. It fires the
ops wrapper, which supervises exactly one tick and appends one JSONL
run record:

```
Task Scheduler / systemd timer (every 15 min, per-user, no elevation)
  └─ mycontrolpanel-check[.exe] check
       --tick-cmd <installDir>/mycontrolpanel[.exe]
       --tick-arg --poll-headless
       └─ app binary --poll-headless        (frozen argv, Lina's contract)
            → toast via NotificationHook.build (transition-only)
            → stdout: one contract JSON line
       → append <stateDir>/headless_runs.jsonl (one record per run)
```

Why the wrapper: Task Scheduler / systemd discard tick stdout, so
without supervision there is no durable per-run history. The wrapper
adds the ledger without changing what the tick evaluates or how it
notifies — poll-evaluate-notify semantics stay Lina's frozen pipeline.

Route invariants (enforced by `verify`, see §4):

- The embedded poll argv is exactly `--poll-headless` — never
  re-templated, never extended with secret material (the wrapper
  refuses secret-bearing argv before spawn).
- Per-user scope, no elevation, no stored passwords, no
  `Environment=` secrets (Linux), `InteractiveToken` + `LeastPrivilege`
  (Windows). `verify` reuses `HeadlessSecurity.validateSchedulerArtifact`
  verbatim for the verdict, plus template-fidelity (§4).
- macOS is Elizabeth's rail (LaunchAgent scope decision, t_a0fe4895):
  `install` refuses on macOS with guidance; use the manual page above.

## 2. Prerequisites (same as the manual path)

1. Install the app, open it once, add at least one server.
2. Settings → background alerts toggle ON (default OFF). The headless
   tick honors the shared `background_alerts` pref and exits `2` when
   OFF — and the managed `install` runs a preflight tick first, so it
   refuses to install a scheduler that could never fire (§3).
3. If the Biometrics app-lock toggle is ON, the tick treats the vault
   as locked and exits `2` (no headless prompt). Turn it OFF on a
   machine you want polling on, or accept skips.

Get the wrapper binary: compile from the repo
(`dart build cli -t bin/mycontrolpanel_check.dart -o <out>`; the
shipped bundle lands at `<out>/bundle/bin/mycontrolpanel_check[.exe]`),
or use the copy shipped by packaging (Aisyah — see §8).

## 3. Install (consent-gated)

Windows (non-elevated PowerShell), Linux (no sudo) — same shape:

```powershell
# Windows
mycontrolpanel-check.exe install `
  --install-dir "$env:LOCALAPPDATA\MyControlPanel" `
  --wrapper "$env:LOCALAPPDATA\MyControlPanel\mycontrolpanel-check.exe"
```

```sh
# Linux
mycontrolpanel-check install \
  --install-dir ~/.local/share/mycontrolpanel \
  --wrapper ~/.local/share/mycontrolpanel/mycontrolpanel-check
```

What install does:

1. Preflight: one supervised tick of
   `<installDir>/mycontrolpanel[.exe] --poll-headless`. Non-zero…
   anything but exit 0 aborts the install: exit 2 with a consent
   reason means "enable Settings → background alerts first"; transport
   failures mean "fix reachability first". Override with `--force`
   (CI smoke does — there is no app binary on a runner — and the gate
   itself is unit-tested).
2. Fills the managed artifact from Lina's template
   (`scripts/headless/windows/mcp-poll-task.xml` /
   `linux/mcp-poll.{service,timer}`): triggers, principals, settings,
   and (Linux) the timer are preserved; only the Exec action routes
   through the wrapper. Fails loud (`StateError`) if the template's
   Exec anchors move — sync with Lina, never fork the schedule.
3. Windows: registers per-user task `\MyControlPanel\poll-headless`
   via `schtasks /Create` (UTF-16 XML, matching the template's declared
   encoding). Linux: writes `~/.config/systemd/user/mcp-poll.{service,timer}`
   (mode 0600), `daemon-reload`, `enable --now`.

Useful flags: `--task-path` / `--unit-name` (side-by-side installs,
CI uses test names), `--unit-dir` (override unit location),
`--sandbox <dir>` (write artifacts to a directory instead of touching
the live scheduler — CI smoke), `--no-reload` (with `--sandbox`),
`--template-dir` (template override), `--force` (skip the gate).

## 4. Verify

```powershell
mycontrolpanel-check.exe verify     # Windows: live task
```

```sh
mycontrolpanel-check verify         # Linux: live units
mycontrolpanel-check verify --sandbox <dir>   # sandbox artifact
mycontrolpanel-check verify --artifact <file> # any filled XML (Windows)
```

Checks, in order:

1. Extract the Exec action (Command/Arguments or ExecStart) and run
   the frozen validator — per-user scope, no elevation, exact
   `--poll-headless` invocation, no secret material.
2. Template fidelity: the installed artifact must equal Lina's
   template outside the Exec action (Windows: comments normalized —
   the managed copy drops the template's header comment because it
   names `--poll-headless`, which is illegal inside an XML comment
   and makes schtasks reject the file; see §7).
3. Linux only: no `Environment=` lines, timer byte-identical to the
   template, service file mode sane.

Exit 0 = clean, 1 = violations printed (each prefixed `verify
VIOLATION:`). Run after every install, upgrade, or hand-edit.

## 5. Status — stale runs and missed heartbeats

```powershell
mycontrolpanel-check.exe status [--json] [--stale-after-min 30]
```

```
scheduler: installed (schtasks:\MyControlPanel\poll-headless) [windows]
last supervised run: 2026-11-02 17:40:01 — verdict: FRESH
```

Verdicts: `fresh` (last run within `--stale-after-min`, default 30 =
2× the 15-minute interval), `stale` (older), `never-ran` (empty
ledger). `missedHeartbeat: true` (JSON) / `MISSED HEARTBEAT` (human)
means the scheduler artifact exists but no fresh run landed — the
firing chain is broken somewhere between the OS trigger and the
ledger. A `(hint: last run skipped on consent …)` suffix means the
most recent record is a consent skip — re-check the toggle, not the
scheduler.

State locations: run ledger `<stateDir>/headless_runs.jsonl` (JSONL,
schema v1 — see `lib/ops/run_ledger.dart`); tick state
`headless_state.json` next to it (contract §4). Deleting the ledger
only resets observability (verdicts go `never-ran`); deleting the
tick state resets dedup (next firing tick notifies once). Server
list, vault entries, and prefs are never touched by any lifecycle
command.

## 6. Uninstall

```powershell
mycontrolpanel-check.exe uninstall
```

```sh
mycontrolpanel-check uninstall [--sandbox <dir>] [--no-reload]
```

Removes the task / timer + service (Linux also `disable --now` +
`daemon-reload`). Never touches the ledger, the tick state, servers,
vault, or prefs. Verify removal with `status` (should report `not
installed`) — `verify` after uninstall exits 1 by design (nothing
to validate against).

## 7. Upstream template issues vs schtasks (fixed)

`scripts/headless/windows/mcp-poll-task.xml` used to not register
as-is on current Windows images — two defects, both reproduced with
`schtasks /Create` on the unmodified template (which also meant the
manual install path via `install-windows.ps1` hit the same wall):

1. The header comment contained the literal text `--poll-headless`.
   A double hyphen is illegal inside an XML comment → `(11,63):
   incorrect comment syntax`.
2. The `<AllowDemandStart>true</AllowDemandStart>` line in
   `<Settings>` was rejected outright (`unexpected node`) in any
   position — bisected on CI with identical artifacts (register
   without it, fail with it). The element defaults to true when
   omitted, so demand-start (`schtasks /Run`) keeps working.

Fixed on Lina's card t_f25d2a50: the comment was reworded (no `--`
inside it) and the `<AllowDemandStart>` line was dropped from both
the headless template and the sibling
`scripts/mcpoll/windows/mcp-poll-task.xml` (same parser wall on its
manual path). The managed `install` keeps dropping the comment and
the line from the generated artifact defensively (pinned by
`test/ops_lifecycle_test.dart`; template fidelity normalizes both
sides, so the normalization is a no-op on the fixed templates).

Live re-verification on a standard-user Windows token (Zara, 2026-11-08)
found a third wall §7 missed: an unscoped `<LogonTrigger>` (fires at
any logon) makes `schtasks /Create` demand elevation — `Access is
denied` for non-elevated installs, while the elevated CI runner in
`ops-smoke.yml` stays green and masks it. Fixed by scoping the trigger
to the installing user (`<UserId>` filled from `%USERDOMAIN%` +
`%USERNAME%` by `install-windows.ps1`, from `InstallOptions.installUser`
by the managed `install`); `verify` flags unscoped triggers and
fidelity normalizes only the identity text. The sibling
`scripts/reliability/windows/` hardened template still carries the
unscoped trigger — Nadia's follow-up before it is used for installs.

## 8. CI + packaging notes

- `.github/workflows/ops-smoke.yml` (this rail's gate, runs on
  Windows + Linux when ops files or the headless templates change):
  analyze slice → ops unit tests → compile the wrapper (`dart build
  cli`) → `dart tool/ops_smoke.dart` (sandbox install → fire twice
  against the fake tick → assert payloads + 2 ledger records → status
  fresh → verify clean → uninstall → verify fails closed) → Windows
  live `schtasks /Create /Query /Delete` round-trip of the filled XML
  with a per-run task name (the real OS parser is the final judge).
- `tool/ops_smoke.dart` is also the local repro: same flags, same
  assertions, runnable from any checkout.
- Packaging (Aisyah): ship `mycontrolpanel-check[.exe]` next to the
  app binary so `--install-dir` + `--wrapper` resolve on user
  machines; the managed task needs no elevation and no secrets at
  install time. Until then, compile from source (§2).

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `install` refused: consent reason | background alerts toggle OFF | Settings → background alerts ON, re-run |
| `install` refused: transport reason | agent :9108 + SSH unreachable | fix reachability; preflight re-runs on retry |
| `status` STALE, scheduler installed | machine asleep / task missed / wrapper failing | `ledger --tail 5` for exit codes; `verify`; Windows: Task Scheduler history |
| `MISSED HEARTBEAT`, ledger `never-ran` | scheduler never fired (logon trigger needs a logon; timer needs lingering on headless Linux) | Windows: log off/on or `schtasks /Run`; Linux server: `loginctl enable-linger` |
| `verify` VIOLATION: drifted outside Exec | hand-edited artifact or template moved | reinstall from the template |
| `verify` VIOLATION: secret material | hand-added `--token`-style args | remove them — vault-only reads; escalate to Alya |
| Toast on every tick | tick state deleted/unwritable | check per-user state dir permissions |
| `verify` finds nothing after uninstall | expected — nothing installed | `install` again; exit 1 here is the pass signal in smoke |
