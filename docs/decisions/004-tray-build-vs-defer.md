# Decision 004 (PROPOSED — needs owner call): Tray mode — build in Beta.2 vs defer

Status: **proposed** — Sofia (CEO) to owner, 2026-11-02. Decides the fate of
`docs/project/tray-mode-plan.md` (Rina, window 2026-11-16 → 2026-12-07,
milestone `v1.0.0-beta.2`, exit review 2026-12-07). No engine work lands
until the owner picks A or B. Engineering input below is advisory only,
sourced from Rina's plan — no new estimates invented here.

## Context

Beta.1 ships foreground alerts only (app open) + an opt-in mobile background
slice. Anything "while the app is closed" on desktop needs tray mode: a
headless poll CLI (`--poll-headless`, TM-1, Lina freezes contract by
2026-11-21) + per-user OS scheduler wiring (Windows Task Scheduler + Linux
systemd timer TM-2, macOS menu-bar helper TM-3) + tray shell UX (TM-4) +
quality gate (TM-5, Farah) + per-OS QA matrices (TM-6, Balqis, closes
2026-12-03) + runbooks/comms (TM-7) + tracking (TM-8). Security boundary is
frozen in ADR-003 (Alya): vault-only reads, no elevation, consent-gated,
fail-closed exit 2. Full WBS/RACI/critical path: `docs/project/tray-mode-plan.md`.

## Option A — Build in Beta.2 (Rina's plan, 3 weeks)

Cost: the full delivery team for ~3 weeks (Lisa/Lina TM-1, Zara TM-2,
Elizabeth+Nurul TM-3/TM-4, Kira design, Farah TM-5, Balqis TM-6, Ain+Naura
TM-7, Shiela+Maisarah TM-8) plus Alya's TM-2 security review and
Burhanah's asset verification — both are Beta.2 exit items, not optional.
Delivers the single most-asked on-call story: closed-app toast on
Windows + Linux + macOS with exactly-once rail + honest staleness.
Risks carried: scheduler credential exposure (H, mitigated by ADR-003),
TM-1 contract churn breaking parallel tracks (H, freeze 2026-11-21),
macOS signing scope fallback to menu-bar-only (M), QA combinatorial blowup
(M, matrix frozen 2026-11-23). Slip rule: any 3+ day critical-path slip
escalates to Sofia via Rina same-day.

## Option B — Defer past v1, ship beta.1 as the background story

Cost: zero delivery weeks; the "what never to promise" line in the sales
kit stays (no closed-app push) and every alerts claim stays foreground-only
(see `docs/sales-kit-review.md` — kit already carries this qualifier).
Saves ~3 team-weeks for Phase 1 mock-killing (#16 GitHub, #18 CI/CD) and
Phase 3 hardening, which gate v1 harder than tray does. Risk: on-call buyers
(the 3 a.m. disk-full segment) hear "app must be open" and walk; the tray
epic (#119 + children #121–#125) goes stale and needs re-planning later.
Mitigation if deferred: keep the Beta.2 milestone open but undated, freeze
ADR-003 + privacy note as the standing contract so a restart costs planning,
not re-architecture.

## Proposal

**Option A — build it**, on three conditions: (1) Lina freezes the TM-1
contract by 2026-11-21 with no post-freeze changes without Rina sign-off;
(2) Aisyah spikes the macOS signing path in week 1 so the LaunchAgent-scope
fallback is decided early, not at the gate; (3) Balqis freezes the QA matrix
by 2026-11-23 and Burhanah verifies only matrix-green assets. If any of the
three misses, the CEO pulls the plug to Option B at the 2026-11-28
convergence point rather than dragging a half-built tray into December.

Rationale: closed-app delivery is the only Beta.2 exit criterion buyers can
feel; everything else in the window is docs. The security contract is already
frozen (ADR-003), the plan is staffed and dated, and deferral's saved weeks
buy mock-killing progress at the price of the sharpest sales story we have.

## Resolution

- [ ] Owner picks A (build) / B (defer) — date: ____
- On A: Rina opens the Beta.2 burndown cadence 2026-11-16; Sofia tracks the
  three conditions above.
- On B: milestone `v1.0.0-beta.2` stays open undated; sales kit keeps the
  foreground-only qualifier; revisit post-v1 with this memo as the restart
  brief.
