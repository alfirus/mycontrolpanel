# Sales-kit review — 2026-11-02 (Syafiqah + Naura, recorded by Sofia)

Reviewers: Syafiqah (Sales Manager — kit safety for live calls), Naura (CMO —
claim accuracy vs README matrix). Method: independent parallel review of
`docs/sales-one-pager.md`, `docs/sales-playbook.md`, `docs/launch.md`,
`docs/packaging.md`, `docs/social-teasers.md` + README cross-check. Full
notes in the review thread; this file locks the findings + fixes.

## Verdict

SAFE for a freelancer/homelab soft-launch selling a free MIT trial + live
demo — after the fixes below. NOT safe for any paid/premium conversation or
any promise in writing beyond "MIT, RM0, community support."

## Fixes required before the first call (owner: Syafiqah + Naura)

1. Alerts language → foreground-only everywhere: "badge + snack while the app
   is open; no background polling/push while closed (roadmap)". Files:
   one-pager use-case #4 + closes, `launch.md` feature block 4, outreach
   `03-demo-invite.md`. (Both reviewers flagged independently.)
2. Deploys timeline → demo data in the same breath: one-pager use-case #3 +
   close #3; never the default demo — GitLab segment is the live one.
3. README hero line qualifies GitHub/CI-CD/Security as UI-ready (the kit is
   honest; the README top line undercuts it).
4. ROI math stays illustrative-only: always spoken "for example" + "measure
   your own week"; never pasted into a proposal email as a researched claim.
5. `launch.md` pricing table gets a DRAFT — INTERNAL ONLY banner; only the
   Free/MIT line may be promised until Sofia + Finance sign PR #28.
6. Playbook pipeline file: create `sales-pipeline-2026-11.md` from the
   stated convention, or every touch goes unlogged.
7. Launch-blocker checklist (Naura): release tag for the "Get the app" CTA,
   green gate, re-captured screenshots, 1–2 real testimonials (never
   invented), pricing sign-off, in-ship honesty labels (AI BYO-key, DEMO
   banners, background opt-in OFF + staleness line), roadmap↔README sync.
8. Open confirmations to engineering (via Sofia → Maisarah): biometric
   enforcement state (kit may be underselling `local_auth`) and Sentry
   opt-in state (kit says placeholder; repo shows a toggle) — sync before a
   security-buyer call.

## Follow-ups (not blocking the soft-launch)

- Roadmap matrix sync to README "Done" reality (GitLab live, background
  beta.1, biometric, Sentry) — Rina's docs queue.
- Hero subhead: "stream" → "refresh (manual rescan / tab switch)".
- "Grafana insight without the stack" → "lightweight live metrics + p95;
  not a Grafana replacement (no retention/export yet)".
- AI pitch always carries "(bring your own key or run Ollama locally)".

Signed: Sofia (CEO) 2026-11-02 · Syafiqah verdict: conditional GO ·
Naura verdict: conditional GO (two gates: foreground-only alerts, demo-data
deploys).
