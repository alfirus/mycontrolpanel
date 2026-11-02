# GO/HOLD Pack — Beta.2 Alerting Gate (QA → Burhanah)

Owner: Balqis (QA Engineer) · Verdict owner: Burhanah (Release Verifier,
GO/HOLD is binding) · Date: 2026-11-02 · Milestone: `v1.0.0-beta.2`
Inputs: `docs/qa/test-plan-beta.md`, `docs/qa/release-checklist.md`,
`docs/project/tray-mode-plan.md` (TM-6), ADR-003.

## QA recommendation: HOLD (device-lab ★ rows pending) — CI lane GO

The deterministic CI lane is fully green; the guarded device-lab lane has
not run live rows yet. Per the release checklist, any unchecked P0 box =
HOLD, and the ★ lab rows are P0. This pack is the honest snapshot:
merge-ready evidence below, lab receipts outstanding.

## Evidence (receipts, not claims)

| Gate area | QA signal | Receipt |
|-----------|-----------|---------|
| CI harness (AM-C/S/F/U/B/D/M, 25 rows) | GO | PR #134 (merge `babb250`): `test`, `analyze`, `osv-scan`, `gitleaks`, build-matrix all pass |
| Beta plan + release checklist docs | GO | PR #136 (merge `77d69b7`): `test`, `analyze`, `markdown links`, builds pass |
| Device-lab workflow (guarded) | GO (lane defined, dry-run green) | This PR: `device-lab.yml` dispatches manual-only, fail-closed without `LAB_SSH_PRIVATE_KEY` |
| Consent (granted/denied/revoked) | GO in CI | AM-C1–C5 green in #134's `test` job |
| Stale honesty + backoff caps | GO in CI | AM-S1–S6 green in #134's `test` job |
| Cold start + alpha.2 upgrade | GO in CI | AM-F1–F3, AM-U1–U4 green in #134's `test` job |
| Battery-saver / OS-killed | GO in CI | AM-B1–B4 green in #134's `test` job |
| Foreground-vs-closed exactly-once | GO in CI | AM-D1–D5 green in #134's `test` job |
| Mobile live rows (DL-A1–A7) | PENDING | No lab run yet — dispatch `device-lab` lane `mobile-consent` |
| Windows closed-app ★ (DL-W1/W2) | PENDING | No lab run yet — lane `desktop-windows` |
| Linux closed-app ★ (DL-L1/L2) | PENDING | No lab run yet — lane `desktop-linux` |
| macOS closed-app ★ (DL-M1) | PENDING | No lab run yet — lane `desktop-macos` |
| Scheduler hardening (DL-W5/L3, Alya TM-2) | PENDING | Alya review open; AM-B4/AM-M3 pin the policy in CI |

## Blocking map (what fails the gate)

- HOLD triggers: any ★ lab row red; any P0 defect in install/consent/
  exactly-once/vault scope; Alya TM-2 review not closed; scheduler argv
  carrying secret material (gitleaks + AM-B3 must both be clean).
- Non-blocking: copy nits (P2) ship with known-issue notes.

## What Burhanah needs to flip this to GO

1. Dispatch the `device-lab` workflow per lane (`mobile-consent`,
   `desktop-windows`, `desktop-linux`, `desktop-macos`) with
   `confirm=I-UNDERSTAND-MANUAL`; attach the run ids here.
2. Fill the ★ receipts in `docs/qa/release-checklist.md` sections C–D.
3. Confirm Alya's TM-2 scheduler review is closed.
4. Verdict: GO only when every P0 box is checked with a receipt;
   otherwise HOLD naming the failing box.
