# Beta DONE checklist — MyControlPanel (beta.1 exit)

Owner: Sofia (CEO) · Verifier: Burhanah (Release Verifier — verdicts binding,
only the owner can waive) · Date: 2026-11-02
Companions: `docs/release-gate.md` (v1 bar), `docs/release-gates.md`
(Burhanah executable gate C1–C6 + proof bundle, merged #128),
`docs/qa/release-gates.md` (Burhanah lanes), `docs/qa/go-hold-checklist.md`
(Balqis input), `docs/STATUS.md` (tag checklist), `docs/roadmap.md` Phase 2.

Scope: beta.1 = foreground alert rail + mobile background slice + biometric
lock enforcement + metrics history. Closed-app tray delivery is Beta.2
(`docs/project/tray-mode-plan.md`), explicitly OUT of this checklist.

## 1. Static gates (all green on the release PR)

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` green.
- [ ] `flutter test` green (incl. `qa_regression_test`,
      `qa_mock_real_gap_test`, `release_gate_proof_test` R1–R8).
- [ ] `security.yml` green (analyze + OSV + gitleaks).

## 2. Live-data bar (no MOCK-tab ships as live)

- [ ] Metrics / crons / apps / alerts / logs populate from a real server
      over SSH + `:9108` agent; demo content only when no servers exist.
- [ ] GitHub / CI-CD / Security tabs carry an explicit DEMO banner unless
      their wiring issue closed in the same release (#16 / #18 / Security
      live-source-or-gated per `docs/qa/release-gates.md` lanes).
- [ ] AI chat labels replies live vs local/demo honestly.
- [ ] Log tail streams live over SSH in release (no simulated stream).

## 3. Credentials + consent honesty

- [ ] Fresh install: secrets in OS keychain/keystore (`SecureStore`), never
      plaintext in prefs; upgrade path migrates once (`migrateIfNeeded`).
- [ ] Background alerts default OFF; enabling copy reads
      "Polls your servers every ~15 min in the background."
- [ ] Staleness line shows "last checked Xm ago" — never silent.
- [ ] No `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` on Android (store-review
      red flag); battery exemption stays manual in-app guidance.

## 4. Builds + update path

- [ ] Release builds succeed on all five targets (macOS, Windows, Linux,
      Android APK, iOS IPA).
- [ ] In-app update path verified against a draft GitHub Release; asset
      names match the updater contract + `SHA256SUMS.txt` present.
- [ ] Linux clean-container check (incl. `libsecret-1-dev`); macOS sandbox
      notes still true against current Xcode.

## 5. Docs + hygiene

- [ ] README screenshots match current UI; README matrix + roadmap reflect
      shipped scope.
- [ ] CHANGELOG entry for the tag; tag notes = closed milestone issues.
- [ ] STATUS.md post-release entry within 48h.

## 6. Known-issue pins (ship only with the note attached)

- [ ] #61 Security Watch mock — excluded from all GO claims.
- [ ] #62 static KPIs (Uptime/Errors/Req-min) — never cited as evidence.
- [ ] #63 log-tail mock bleed on fetch failure — noted.

## Sign-off

| Role | Name | Verdict | Date |
|---|---|---|---|
| Release Verifier | Burhanah | GO / HOLD (circle) | ____ |
| CEO release approval | Sofia | approved | 2026-11-02 (checklist locked; verdict pending Burhanah) |

A HOLD names the failing box + issue number; the tag aborts. Waiver path:
owner decision recorded in-repo, tag match required.
