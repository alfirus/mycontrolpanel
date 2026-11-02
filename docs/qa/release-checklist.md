# Release Checklist — Beta.2 (`v1.0.0-beta.2`)

Owner: Balqis (QA input) · Verdict: Burhanah (Release Verifier, GO/HOLD) ·
Program: `docs/project/tray-mode-plan.md` · Test plan: `docs/qa/test-plan-beta.md`
GO/HOLD pack: `docs/qa/go-hold-pack-beta.md`

Check every box with a receipt (CI run id, read-back output, or lab note).
A worker's summary is a claim; the receipt is the fact. Any unchecked P0
box = HOLD.

## A. CI gates (all required, branch protection)

- [ ] `test` (`ci.yml`): `flutter test` green, including
  `test/alerting_matrix_test.dart` (25 rows), `test/headless_security_test.dart`,
  `test/release_gate_proof_test.dart`, `test/qa_regression_test.dart`.
  Receipt: CI run id + `All tests passed`.
- [ ] `analyze` (`security.yml`): `flutter analyze --no-fatal-infos
  --no-fatal-warnings` clean. Receipt: CI run id.
- [ ] `osv-scan` (`security.yml`): no new advisories on `pubspec.lock`.
  Receipt: CI run id.
- [ ] `gitleaks` (`security.yml`): full-history scan clean — no tokens, key
  paths, or passphrases in scheduler args/docs/logs. Receipt: CI run id.
- [ ] Build matrix (`build-matrix.yml`): desktop + mobile smoke builds pass
  on the candidate. Receipt: CI run ids.

## B. QA harness (CI lane)

- [ ] All AM rows green in the candidate's `test` job (§2 of the test plan).
  Receipt: `test` job log line for `alerting_matrix_test.dart`.
- [ ] No P0/P1 defects open outside the filed Security scope. Receipt:
  issue query (open P0/P1 count = 0 or HOLD named).

## C. Device-lab lane (manual, guarded workflow)

- [ ] ★ rows green: DL-A1, DL-A2, DL-W1, DL-W2, DL-L1, DL-L2, DL-M1.
  Receipt: lab notes (OS, install path, window state, toast observed ≤ interval).
- [ ] Consent + vault rows green: DL-A3, DL-W3, DL-W4. Receipt: exit-2 logs
  (secret-free) + no-toast confirmation.
- [ ] Scheduler hardening rows green: DL-W5, DL-L3 (+ Alya TM-2 review
  closed). Receipt: validation output + review sign-off.

## D. Assets + docs (Burhanah verifies, Ain/Naura publish)

- [ ] Release assets attached from `release.yml` (macOS zip, Windows zip,
  Linux tarball, SHA256SUMS). Receipt: asset list + checksums.
- [ ] Runbooks published (install/uninstall/troubleshooting per OS) and
  beta comms sent. Receipt: doc links + comms note.
- [ ] No MOCK-tab ships as live: unwired tabs carry an explicit demo-mode
  banner. Receipt: UI pass note (see `docs/release-gate.md`).

## E. Tag + sign-off

- [ ] QA input recorded: GO or CONDITIONAL GO with the blocking map
  (P0 = block; P2 = ship with known-issue note).
- [ ] Burhanah verdict: GO / HOLD with receipts (this checklist + the
  GO/HOLD pack). HOLD names the failing box.
- [ ] Tag `v1.0.0-beta.2` cut via `release.yml` only after GO.
