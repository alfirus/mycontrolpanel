# GitHub-API wiring — review guide (token scope, secure storage, PR linkage)

For reviewers of the GitHub-tab wiring work (issues #19, #21, #23, #25).
The client already exists (`lib/services/github_service.dart`); this note pins
the non-negotiables so review stays mechanical.

## 1. Token scope (least privilege)
- Classic PAT: `repo` scope only. Never request `admin:*`, `delete_repo`,
  `workflow` (write), or org admin scopes — the app only reads.
- Fine-grained PAT (preferred): single-repo, read-only —
  Contents (read), Issues (read), Pull requests (read), Actions (read).
- `GithubService.validate()` (`GET /user`) is the scope smoke test: a 200 means
  the token authenticates; a 403/404 on a repo endpoint afterwards means the
  scope or repo access is wrong, not the token. Keep that distinction in errors.
- Token entry must be paste-only with immediate `validate()` feedback; never
  pre-fill, log, or include the token in error text or crash reports.

## 2. Secure storage (Option A — owner-mandated, decision PR #17)
- All tokens/passwords go through `SecureStore` (`flutter_secure_storage` →
  Keychain / Keystore / libsecret). SharedPreferences holds only `secure:<key>`
  markers, never secret material.
- PR #17 proposes removing the plaintext-prefs fallback in
  `SecureStore.readServers()` after one confirmed migration cycle — until that
  lands, reviewers must confirm every new credential path uses `writeSecret` /
  `readSecret` and never writes raw secrets to prefs.
- Checklist for any PR touching credentials:
  - [ ] No secret in logs, analytics, screenshots, or error strings
  - [ ] Migration path covered (`migrateIfNeeded`, idempotent via flag)
  - [ ] Linux: `libsecret-1-dev` present (release build dependency)
  - [ ] Nothing in the PR body/templates suggests prefs-storage is acceptable

## 3. PR linkage (repo conventions)
- One feature branch per contribution (`feat/<short-name>`), one PR against
  `main`, never push `main`.
- PR body uses the template: `Closes #<n>` for the MOCK-gap issue it retires
  (#19 GitHub tab, #21 Actions timeline, #23 alert polling, #25 secure storage).
- In-app linkage: every issue/PR row deep-links its `html_url` (open on
  github.com); Actions runs link the run URL. No dead rows.
- Mock data (`mock_data.dart`) stays only as offline fallback, badged DEMO in
  the UI — review must reject any PR that presents mock rows as live.
- Green CI (`analyze`, `gitleaks`, `osv-scan`, `test`) is required by branch
  protection; PR #13's pre-merge `analyze` failure (`num` vs `double`) is the
  cautionary tale — fix-then-merge, never merge red.
