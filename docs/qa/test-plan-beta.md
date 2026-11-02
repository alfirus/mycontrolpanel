# Beta Test Plan — Alerting + Background Delivery (Beta.2 exit)

Owner: Balqis (QA Engineer) · For: Burhanah (Release Verifier, GO/HOLD) +
Rina (program gate) · Date: 2026-11-02 · Milestone: `v1.0.0-beta.2`
Program: `docs/project/tray-mode-plan.md` (TM-6) · Architecture:
`docs/design/05-background-alerting.md` §8 · Security: ADR-003
(`docs/decisions/003-tray-headless-security.md`)

This plan proves the Beta.2 exit clause: a closed-window firing signal
(failed unit + disk ≥80%) reaches the OS rail on Windows + Linux + macOS,
exactly once across rails, under the shared opt-in with honest staleness,
vault-only credentials, no-elevation install.

## 1. Entry / exit criteria

Entry: `main` green on all four required gates (`test`, `analyze`,
`osv-scan`, `gitleaks`) + build-matrix smoke builds pass on the candidate.
Exit (QA GO input to Burhanah): every P0 row below is green in its lane,
no open P0/P1 defects outside the filed Security scope, and the
`docs/qa/release-checklist.md` sign-off boxes are checked with receipts
(CI run ids, not pasted logs).

## 2. CI lane (deterministic, runs per PR)

Executable: `test/alerting_matrix_test.dart` (25 rows, AM-C/S/F/U/B/D/M).
No WorkManager / BGTaskScheduler / local-notifications calls; the tick runs
with an injectable `fetchAlertsFor`; seeded servers carry empty credentials
so the keychain is never touched.

| ID | Matrix | Oracle (pinned in test) |
|----|--------|-------------------------|
| AM-C1–C5 | Consent denied/granted/revoked | Default OFF on every rail; opt-in persists; revoke is immediate; headless gate exits 2 on consent OFF; consent copy carries `~15 min` |
| AM-S1–S6 | Stale thresholds | Backoff 5m→10m→20m→40m→cap 1h; warn 0.85 / crit 0.95; never/just-now/min/hr/day copy; future-stamp never negative; empty math never breaches; empty-host tick still stamps |
| AM-F1–F3 | Cold start | Empty prefs: no consent, no stamp, no badge, empty body; first firing batch is entirely fresh; headless gate skips (exit 2) |
| AM-U1–U4 | Alpha.2 upgrade | `secure:` + secret resolves; legacy plaintext marker never resolves (heal is UI-only); locked vault denies (exit 2, `denied` reason); marker-without-secret forces re-entry |
| AM-B1–B4 | Battery-saver / OS-killed | Throwing fetch never sinks the tick; one sick host never sinks a sibling; scheduler argv scan flags `--token=` / `secure:` material; per-user + no-elevation + exact `--poll-headless` validated on all three schedulers |
| AM-D1–D5 | Desktop foreground-vs-closed | One shared `background_alerts` pref (no second toggle); desktop payload == `NotificationHook.build` verbatim on five shapes; shared seen-set gives exactly-once (second rail sees nothing fresh); fan-out stamps the shared check; rails silent without consent/payload, never throwing |
| AM-M1–M3 | Mock contract | Scheduler/plugin entry-points are safe no-ops in CI; injected fetch drives the tick end to end; tampered entry-point rejected on every scheduler |

## 3. Device-lab lane (manual, guarded — real hosts, schedulers, toasts)

Runs only from the guarded `device-lab` workflow (`workflow_dispatch`,
human-approved, fail-closed without lab secrets). One row = one OS ×
install path × window state × consent state. P0 rows are marked ★.

### 3.1 Mobile (Android + iOS)

| ID | Case | Steps / oracle | Expected |
|----|------|----------------|----------|
| DL-A1 ★ | Consent denied | Fresh install, toggle OFF, trigger firing fixture | No background work scheduled, no toast |
| DL-A2 ★ | Consent granted | Toggle ON (~15 min copy visible), trigger fixture | Toast ≤ one scheduler interval |
| DL-A3 | Consent revoked | ON → trigger → OFF → trigger again | First toasts, second never fires; work cancelled |
| DL-A4 | Stale honesty | Airplane mode 1h with toggle ON | Status reads `last checked 1 hr ago`, never `just now` |
| DL-A5 | Cold start | Fresh install, never opened after reboot | No crash, `never checked yet` until first tick |
| DL-A6 | OS-killed / battery | Battery-saver ON (Android) / Background-Refresh OFF (iOS) | Ticks defer or back off; no hot loop; staleness line stays truthful |
| DL-A7 | Upgrade | Alpha.2 build with legacy creds → install beta | Markers migrate, plaintext never reaches the poller |

### 3.2 Desktop closed-app (Windows Task Scheduler / systemd user timer / macOS helper)

| ID | Case | Steps / oracle | Expected |
|----|------|----------------|----------|
| DL-W1 ★ | Windows closed-window | Window closed, failing unit + disk ≥80% fixture, scheduler tick | OS toast ≤ scheduler interval |
| DL-W2 ★ | Exactly-once | Window open AND scheduler tick on same fixture | One toast total, never two |
| DL-W3 | Consent OFF headless | Toggle OFF, force tick | Exit 2, no toast, nothing written but the stamp |
| DL-W4 | Vault locked | App lock engaged, force tick | Exit 2, no prompt, no read attempted |
| DL-W5 | Tampered artifact | Edit task args to add `--token=x` | Validation rejects; TM-6 re-check green |
| DL-L1 ★ | Linux closed-window | Same as DL-W1 via systemd user timer | OS notification ≤ interval |
| DL-L2 ★ | Linux exactly-once | Same as DL-W2 | One notification total |
| DL-L3 | Linux per-user scope | `systemctl --user` unit file mode + path | `~/.config/systemd/user/`, mode 0600, no system unit |
| DL-M1 ★ | macOS closed-window | Same as DL-W1 via menu-bar helper | OS notification ≤ interval |
| DL-M2 | macOS consent prompt | First fire after install | User-allow prompt once, then toasts |

## 4. Defect filing (QA → lead → owner)

Balqis files against the owning developer via Lina: Lisa (headless CLI),
Zara (scheduler wiring), Elizabeth/Nurul (tray + menu-bar), Farah
(quality gate), Alya (security boundary). Severity: P0 = gate fails
(anything that breaks a ★ row); P1 = wrong rail/duplicated toast/stale
lie; P2 = copy nits. A P0 blocks the release — the GO/HOLD pack
(`docs/qa/go-hold-pack-beta.md`) records it as HOLD with the receipt.

## 5. Traceability (Beta.2 exit clause → rows)

1. Closed-window firing signal on 3 OSes → DL-W1, DL-L1, DL-M1 (+ AM-B4, AM-M2 in CI).
2. Exactly-once across rails → DL-W2, DL-L2 (+ AM-D3 in CI).
3. Consent + honesty → DL-A1–A3, DL-W3 (+ AM-C1–C5, AM-S3–S6, AM-D4 in CI).
4. No-elevation + vault-only → DL-W5, DL-L3, DL-W4 (+ AM-U1–U4, AM-B3–B4 in CI).
5. Green gates + verified assets → `docs/qa/release-checklist.md`.
