# Beta Operating Budget — MyControlPanel (maintainer view)

Owner: Finance & Accounts (Nafisah). Status: beta planning baseline, 2026-11-02.
Companion workbook: `assets/templates/beta-operating-budget.xlsx` (12-month
budget-vs-actual, best / base / worst scenarios + guardrails + sources).

Rules: public list prices and free-tier limits only — nothing proprietary in
this repo (same convention as `operating-cost-model.md`:
structure + formulas + sources here, real spend lives in the finance
workspace). Syafiqah's pricing builds on these numbers — keep every row
sourced and reviewable. Currency is USD (vendors bill in USD).

## 1. One-time / annual launch fees (year 1)

| # | Item | Amount (USD, vendor list) | Cadence | Why / when | Source |
|---|------|---------------------------|---------|------------|--------|
| L1 | Apple Developer Program | 99 | Annual | Only when shipping iOS via App Store / TestFlight; sideload/desktop-only beta skips it | https://developer.apple.com/programs/ |
| L2 | Google Play developer registration | 25 | One-time | Only when shipping Android via Play; sideload APK skips it | https://support.google.com/googleplay/android-developer/answer/6112435 |
| L3 | Custom domain (`.com` list price) | ~12 | Annual | Registrar list price; free subdomain / GitHub Pages default skips it | https://www.cloudflare.com/products/registrar/ |
| L4 | Code-signing certificates (beta) | 0 | — | Beta uses ad-hoc / self-signed + store signing; no EV cert in beta | `.github/workflows/release.yml` (in-repo) |
| L5 | GitHub repo + Actions free tier | 0 | Included | Public repo; `analyze` + `test` + security gate run inside the free tier (see guardrails) | https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions |
| L6 | Maintainer backend / servers | 0 | — | Local-first architecture: no control-plane servers, no push relay, no telemetry backend in beta | `README.md` (architecture) + `docs/launch.md` |

Year-1 launch-fee total (base): L1 + L2 + L3 = **~136 USD** (99 + 25 + ~12).
Lean beta (no iOS store, no custom domain): **25 USD** (L2 only).

## 2. Monthly burn (base: zero)

The beta has no maintainer meter: the app runs on the user's devices over
their SSH; AI calls use the user's own keys (BYOK / local Ollama); alerts
are in-app only (no push relay until Phase 2 tray work).

| # | Burn line | Base (USD/mo) | Driver | Guardrail | Source |
|---|-----------|---------------|--------|-----------|--------|
| B1 | CI minutes (analyze + test + security gate) | 0 | PRs × minutes per run | Stay inside GitHub Free: 2,000 Actions min/mo + 500 MB storage; batch PRs if close | https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions |
| B2 | API usage (GitHub/GitLab REST, AI assist) | 0 | Calls per seat per day | Beta traffic rides free rate limits; AI is BYOK — maintainer pays no per-call cost | `docs/finance/operating-cost-model.md` buckets 4–5 |
| B3 | Notifications / push relay | 0 | Deliveries per severity | No relay in beta (foreground watcher only); relay spend starts only with Phase 2b tray gate | `docs/design/05-background-alerting.md` + `docs/project/tray-mode-plan.md` |
| B4 | Secure-storage / rotation ops | 0 | Rotations per quarter | On-device keychain only; no HSM / managed-secret spend | `docs/decisions/001-credential-storage.md` |
| B5 | Fixed overhead (licences, standby) | 0 | Flat | No paid seats, no standby infra in beta | `docs/finance/operating-cost-model.md` |

Base monthly burn: **0 USD/mo**. Overage buffer (worst case only): Linux
Actions overage lists at 0.008 USD/min — same GitHub billing source as L5.
1,000 overage minutes ≈ 8 USD/mo; the workbook's worst column carries this
as an explicit buffer row (default 0 until a guardrail trips).

## 3. Free-tier guardrails (tripwire table)

| Guardrail | Limit | Trip action |
|-----------|-------|-------------|
| Actions minutes | 2,000 min/mo, 500 MB storage (GitHub Free) | Batch PRs / trim matrix; reforecast before approving any overage |
| iOS distribution | Membership only if TestFlight/App Store used | Sideload + desktop builds stay free |
| Android distribution | 25 USD once for Play; APK sideload free | Defer Play listing to cut 25 USD |
| Domain | Custom domain only if launch kit needs it | Free hosting default keeps L3 at 0 |
| Push relay | No relay spend before Phase 2b gate | Any relay proposal needs Finance sign-off first |

## 4. 12-month scenarios (match the workbook)

| Scenario | Launch fees (yr 1) | Monthly burn | Year-1 total | When it applies |
|----------|--------------------|--------------|--------------|-----------------|
| Best (lean beta) | 25 (Play only) | 0 | **~25** | Desktop + Android sideload, no iOS store, no custom domain |
| Base (full beta) | ~136 (Apple 99 + Play 25 + domain ~12) | 0 | **~136** | All stores + domain, guardrails hold |
| Worst (guardrail trip) | ~136 + overage buffer ~8/mo (~96/yr) | ~8 | **~232** | CI exceeds free tier for a sustained stretch |

Workbook (`assets/templates/beta-operating-budget.xlsx`): launch fees land in
M1; M2–M12 burn-only; TOTAL row sums each scenario; Actual + Variance columns
go live at first close. Variance flag: any line >15% vs base triggers a
reforecast (same rule as `budget-vs-actual-mock-gaps.md`).

## 5. Budget gates (roadmap linkage)

- No paid infra, relay, cert, or store spend lands without Finance sign-off
  against this file (see `docs/roadmap.md` — budget gate).
- Phase 2b tray work (push relay) and Phase 3 observability (Sentry/Datadog
  opt-in) each re-check §2–§3 before their milestone exits: relay/retention
  proposals must name their bucket from `operating-cost-model.md` first.
- Mock→live cutovers (G1–G4 in `budget-vs-actual-mock-gaps.md`) move their
  row from zero-volume to metered the same month and start filling Actuals.

## 6. Break-even pointer (for Syafiqah's pricing)

Per `docs/decisions/002-commercial-packaging.md`: MIT + donations through
v1-ship, no paid tiers, no prices quoted. Break-even for the beta is therefore
**donations vs amortized launch fees**: ~11 USD/mo on the base case
(136 / 12), ~2 USD/mo lean, ~19 USD/mo worst. Any future tier price must clear
its cost floor in `pricing-cost-floor.md` (30% margin buffer) *plus* this
amortized launch share — Syafiqah owns that math; this file owns the inputs.

## 7. Review log

| Date | Reviewer | What was checked |
|------|----------|------------------|
| 2026-11-02 | Nafisah (Finance) | Every row sourced; scenarios tie to workbook; gates linked from roadmap; break-even note in sales kit |

Sources re-verified 2026-11-02 (vendor list prices; re-check annually or when
a guardrail trips).
