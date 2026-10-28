# Engineering delivery plan — MOCK-to-real + v1 hardening (Maisarah)

Sequencing layer on top of Rina's phased roadmap and Sofia's direction:
this doc turns the open MOCK-gap issues into ordered waves with owners,
estimates, and acceptance pointers. Roadmap phases live in the roadmap PR;
per-issue acceptance criteria live on the issues themselves. This file owns
ORDER, OWNERSHIP, and EXIT GATES only.

Source of truth checked 2026-10-28: milestones `v1.0.0-alpha.2` (3),
`v1.0.0-beta.1` (4), `v1.0.0` (5), `GitHub-API wiring` (6).

## Wave 0 — close the credential loop (done, verify only)

| issue | state |
|---|---|
| #25 creds/tokens in SharedPreferences → SecureStore | code on main (`SecureStore` + `SecretHygiene`), guard test enforces |
| #22 secure-storage completion audit | verify matrix in cutover spec §3, then close |

No new code. Owner: Maisarah. Exit: QA (Balqis) ticks the cutover
verification matrix on a fresh install + upgrade path.

## Wave 1 — kill the mocks (milestone 3, alpha.2)

Parallel after Wave 0, in this order per stream (contracts first):

| # | issue | owner | est. |
|---|---|---|---|
| 16 | GitHub Issues/PRs live (token via SecureStore) | Elizabeth + Nurul (UI) | 3d |
| 19 | GitHub tab stops rendering mock issues/PRs/tasks | Elizabeth | 1d (follows 16) |
| 18 | Actions CI/CD timeline live, failure surfacing | Elizabeth + Lisa (shape) | 3d (follows 16) |
| 21 | CI/CD demo deploys → live Actions runs | Elizabeth | 1d (follows 18) |
| 20 | Alert polling: foreground watcher verify, background design | Alya + Balqis (QA) | 2d |
| 23 | Alerts mock-fed → real polling + background delivery | Alya | 3d (follows 20; background needs workmanager — stays flagged) |
| 61 | Security Watch mock unconditional | Alya | 2d |
| 62 | Metrics demo KPIs static/unlabeled in LIVE | Lisa + Kira (labels) | 2d |
| 63 | Log Tail demo mockLogs under LIVE title | Lisa | 1d |

Security review (Alya) runs across the wave: token scopes minimal (`repo`
read?), keychain audit, public-repo hygiene sign-off per quality-gates §3.

Exit gate: every screen in the live-vs-mock matrix shows LIVE data or an
explicit demo label; zero mock renders under a LIVE title.

## Wave 2 — beta hardening (milestone 4, beta.1)

| # | issue | owner | est. |
|---|---|---|---|
| 24 | Biometric app lock enforcement | Elizabeth + Alya (review) | 3d |
| — | Metrics retention policy (no issue yet — file it) | Lisa | 2d |
| — | Push-notification design from Wave-1 poller (needs workmanager) | Alya | design 2d, build next |

## Wave 3 — release hardening (milestone 5, v1.0.0)

| # | issue | owner | est. |
|---|---|---|---|
| 26 | Sentry/Datadog opt-in integration | Nadia/Aisyah (ops) | 3d |
| 32 | Public-MIT posture confirmation (Naura) | hold: need-owner-decision | — |
| — | Release checklist per tag (release-process.md) | Maisarah + Aisyah | 1d |

## Definition of done (every wave item)

1. One feature branch + one PR against `main`; never push `main`.
2. CI green: `test` (ci.yml) + `analyze`, `osv-scan`, `gitleaks`
   (security.yml); build-matrix compiles on shipping platforms.
3. Review checklist answered in the PR body for anything touching
   secrets, SSH, or the agent protocol (`docs/quality-gates.md` §3).
4. Mocks: new service covered by a `Mock*` + `MCP_MOCKS` path.
5. Spec updated (`docs/specs/`) for contract changes; unit tests for new
   parsers/contracts (`test/`).
6. Linked issue closed only after the exit-gate evidence is on the PR
   (screenshot, prefs-XML inspection, or CI log — not a claim).

## Open questions for Rina / Sofia

- Milestones 6 (`GitHub-API wiring`, due 2026-12-30) and 7 (`v1.0-beta`)
  overlap 3/4/5 in scope — propose closing 6/7 as duplicates once this
  plan is accepted, keeping 3/4/5 as the single chain.
- Issues #61–63 are unmilestoned; proposal: add them to milestone 3
  (they are alpha.2 exit-gate items above).
- Background alert delivery needs a workmanager (or equivalent) decision
  before Wave 2 build starts — design-only until then.
