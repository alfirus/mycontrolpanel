# Tray-mode delivery program + Beta.2 exit plan

Owner: Rina (PM) · Status: approved spine, in planning · Updated: 2026-11-02
Milestone (proposed): `v1.0.0-beta.2` · Window: 2026-11-16 → 2026-12-07
Companions: `docs/roadmap.md` (Phase 2b exit gate) ·
  `docs/design/05-background-alerting.md` §8 (closed-app architecture)

## Goal

Ship closed-app alert delivery on desktop via tray mode: the app minimises
to the system tray / menu bar, and a headless poll path delivers firing
signals + failed CI runs through the OS notification rail while no window
is open — with the same payload, consent, and staleness honesty as beta.1.
No remote push (FCM/APNs), no new payload formats.

## Scope

In: headless poll CLI entry-point; Windows Task Scheduler wiring; Linux
systemd user-timer wiring; macOS menu-bar/tray helper; tray shell UX
(icons, menu, settings linkage); alert-quality gate for the headless path;
per-OS QA matrices; runbooks + beta comms; release-asset verification.
Out: remote push relay, exact-time guarantees on mobile OSes (unchanged),
multi-window management beyond the tray shell, GitLab parity.

## WBS

| ID | Workstream | Owner (does) | Support | Target |
|---|---|---|---|---|
| TM-1 | Headless poll CLI (`--poll-headless`): arg contract, exit codes, reuse of `PollPolicy`/`Thresholds`/`NotificationHook.build` verbatim | Lisa (impl), Lina (architecture sign-off) | Farah (threshold consult) | 2026-11-21 |
| TM-2 | Windows Task Scheduler wiring + Linux systemd user-timer wiring (install/uninstall scripts, per-user scope, no elevation) | Zara | Aisyah (packaging), Alya (security review) | 2026-11-26 |
| TM-3 | macOS menu-bar/tray helper (LaunchAgent scope decision, signing/notarisation notes) | Elizabeth + Nurul (impl), Lina (architecture sign-off) | Aisyah (signing), Kira (menu UX) | 2026-11-28 |
| TM-4 | Tray shell UX: icon states (ok/firing/stale), menu (open/mute/quit), Settings linkage, first-run consent copy | Kira (design), Nurul (impl) | Elizabeth | 2026-11-28 |
| TM-5 | Alert-quality gate for headless path: threshold reuse audit, quiet-hours, dedupe/no-double-toast with in-app rail | Farah | Nadia (consulted), Lisa | 2026-11-26 |
| TM-6 | QA matrices per OS × install path + closed-app verification (kill window → fire signal → toast ≤ scheduler interval) | Balqis | Burhanah (release-asset verification) | 2026-12-03 |
| TM-7 | Docs + runbooks (install/uninstall, troubleshooting per OS) + beta comms | Ain (docs), Naura (comms) | Rina | 2026-12-03 |
| TM-8 | Program tracking: milestone hygiene, weekly burndown, gate readiness | Shiela (tracking/milestone), Maisarah (day-to-day delivery) | Rina | ongoing |

## Critical path

TM-1 (headless CLI contract, Lina signs off by 2026-11-21) → TM-2 + TM-3
(scheduler/helper wiring, converge 2026-11-28) → TM-6 (QA matrices +
Burhanah asset verification, 2026-12-03) → Beta.2 exit review 2026-12-07.
Slip rule: TM-1 slipping past 2026-11-21 consumes TM-2/TM-3 float first;
any 3+ day slip on the path escalates to Sofia via Rina same-day.

Off the critical path (parallel float): TM-4 (tray UX ships against the
TM-1 stub contract), TM-5 (quality gate lands any time before TM-6
sign-off), TM-7 (docs draft from §8, finalised after TM-6).

## RACI

Binding deconfliction (dispatcher ruling) is honoured verbatim: Lina owns
headless-CLI architecture, Maisarah drives delivery day-to-day, Shiela
owns tracking/milestone, Alya owns scheduler security review, Balqis owns
QA matrices, Burhanah verifies release assets.

| Decision / deliverable | R | A | C | I |
|---|---|---|---|---|
| Headless CLI contract (args, exit codes, output) | Lina | Rina | Lisa, Farah, Alya | Shiela |
| Scheduler wiring (Task Scheduler / systemd / LaunchAgent) | Zara | Maisarah | Alya, Aisyah | Shiela |
| Scheduler security review (scope, elevation, credential handling) | Alya | Rina | Zara, Lina | Burhanah |
| Tray shell UX (states, menu, consent copy) | Kira | Elizabeth | Nurul, Naura | Ain |
| QA matrices + Beta.2 gate sign-off | Balqis | Rina | Burhanah, Farah | Shiela, Sofia |
| Release assets attached + verified | Burhanah | Rina | Aisyah | Sofia |
| Runbooks + beta comms | Ain / Naura | Rina | Zara, Balqis | — |
| Milestone hygiene + burndown | Shiela | Maisarah | Rina | Sofia |

R = does it, A = answers for it, C = consulted before, I = informed after.
Single-A rule: exactly one A per row; disputes escalate Rina → Sofia.

## Beta.2 exit criteria (mirrored in `docs/roadmap.md` Phase 2b)

1. Headless poll delivers a real firing signal (failed unit + disk ≥80%)
   to the OS notification rail with the app window closed, on Windows +
   Linux + macOS (Balqis matrix green, TM-6).
2. Exactly-once rail: no double toast when window open AND scheduler fires
   (dedupe via `NotificationHook.build` + shared last-seen set, TM-5).
3. Consent + honesty: headless path runs only with the shared
   `background_alerts` opt-in ON (default OFF); stale state shows
   "last checked Xm ago", never silent (TM-4/TM-5).
4. No-elevation install: per-user scheduler/timer install + uninstall
   scripts, credentials from OS vault only — Alya review closed, no
   plaintext secret in scheduler args (TM-2 + Alya).
5. `flutter analyze` + `flutter test` green; release assets attached and
   Burhanah-verified; runbooks published (Ain); beta.2 tag cut via
   `release.yml`.

## Top-5 risks

1. **Scheduler credential exposure (H)** — scheduler args/cli logs leak a
   token or key path. Mitigation: vault-only reads inside the headless
   process, never argv/env; Alya reviews TM-2 before TM-6. Owner: Alya.
2. **TM-1 contract churn breaks TM-2/TM-3/TM-4 in parallel (H)** —
   downstream builds against a moving CLI. Mitigation: Lina freezes the
   arg/exit-code contract by 2026-11-21; changes after freeze need Rina
   sign-off + same-day downstream notice. Owner: Lina.
3. **macOS signing / LaunchAgent scope blocks install (M)** — helper
   refused or unfamiliar consent prompts. Mitigation: Aisyah spikes the
   signing path in week 1; fallback is menu-bar-only (no LaunchAgent) and
   the gate records the reduced scope explicitly. Owner: Aisyah.
4. **Double-toast / missed-toast on rail handoff (M)** — in-app timer and
   headless tick both fire. Mitigation: single shared last-seen set +
   `NotificationHook.build` verbatim on both rails; TM-5 audited inside
   TM-6 matrix (open + closed cases). Owner: Farah (gate), Balqis (proof).
5. **Per-OS QA combinatorial blowup (M)** — 3 OSes × install paths ×
   open/closed × consent on/off. Mitigation: Balqis freezes the matrix by
   2026-11-23 (smoke subset runs per-PR, full matrix at gate); Burhanah
   verifies only matrix-green assets. Owner: Balqis.

## Cadence

Weekly STATUS.md entry (done / in-flight / blocked + burndown vs
`v1.0.0-beta.2`), owned by Shiela (tracking) with Maisarah (delivery).
Rina owns the plan + gate; slippage and scope disputes escalate to Sofia.
