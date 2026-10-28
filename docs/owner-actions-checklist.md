# Owner actions checklist (repo settings needing a human call)

Verified live via `gh` on 2026-10-28 — no action needed unless noted.

## Already in place (leave as-is)
- Description + topics (`control-center`, `flutter`, `ssh`, `server-monitoring`, …) — set.
- Branch protection on `main`: PR required, strict status checks
  (`analyze`, `gitleaks`, `osv-scan`), conversation resolution on,
  enforce-admins on. Required approving review count is **0** — deliberate
  for a solo-owner repo; raising it to 1 would block self-merges.
- Release flow: tag-driven `release.yml` (macOS/Windows/Linux + SHA256SUMS),
  `v1.0.0-alpha.1` already published; in-app updater expects those asset names.
- Labels: `mock-gap`, `github-api`, `actions-timeline`, `alert-polling`,
  `secure-storage`, `ci`, `release` (+ defaults). Milestones: `GitHub-API wiring`, `v1.0-beta`.

## Owner calls (your decision)
- [ ] `delete_branch_on_merge`: currently **off**. Recommend ON (keeps the
  branch list clean; merged feature branches pile up otherwise).
  One-liner: `gh api repos/alfirus/mycontrolpanel -f delete_branch_on_merge=true`
- [ ] Wiki is **enabled** but unused — disable if docs stay in `docs/`.
- [ ] `allow_auto_merge`: currently off. Enable only if you want automerge on green PRs.
- [ ] Squash vs merge-commit: all three methods allowed. Pick one convention
  (suggest squash for feature PRs) and enforce by unchecking the others in
  Settings → General → Pull Requests.
- [ ] Open review: PR #13 (`feat/real-logs-metrics-alerts`) is red on `analyze`
  (`num` vs `double` at `control_center_screen.dart:289-293`). Fix suggestion
  is posted on the PR — merge only after CI goes green.
