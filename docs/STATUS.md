# MyControlPanel Status + Release Cadence

Owner: Rina (PM) · Updated: 2026-10-28

## Weekly status (every Monday)

Post a dated entry below (append, newest last) with: Done / In-flight /
Blocked + burndown against the open milestone (`open / closed` issue counts
via `gh issue list --milestone <name>`) + top-3 risks movement (RISKS.md).
Format:

```text
## 2026-11-03 — v1.0.0-alpha.2 burndown: 4 open / 2 closed
Done: ...
In-flight: ...
Blocked: ...
Risks: ...
```

### Log

```text
## 2026-10-28 — baseline (Rina)
Done: ROADMAP.md / BACKLOG.md (#16,#18,#20,#22,#24,#26) / RISKS.md /
  STATUS.md filed as PRs #15,#27,#29#+status; milestones v1.0.0-alpha.2,
  v1.0.0-beta.1, v1.0.0 created. Prior week: #7-#12 merged (secure storage,
  APM-lite, Projects v2, release workflow fixes, screenshots).
In-flight: PR #13 (real SSH log tail, metrics history + live p95, foreground
  alert watcher) — merge unblocks #20 verification.
Blocked: none.
Risks: no movement; watch list is agent-:9108-auth, dartssh2-SPOF,
  release-pipeline fragility.
Burndown v1.0.0-alpha.2: 4 open / 0 closed (issues #16,#18,#20,#22).
```

## Burndown rule

Burndown counts come from milestone issue state, not this file's prose.
Closing an issue requires its BACKLOG.md acceptance criteria + README
mock-table update in the same PR. Stale (>2 weeks, no comment) issues get a
PM ping comment before reassignment.

## Release checklist (every `v*` tag)

Run in order; abort the tag on any red item.

1. [ ] Milestone complete: all its issues closed with criteria + README updated.
2. [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` green.
3. [ ] `flutter test` green.
4. [ ] `security.yml` gate green on the release PR (analyze + OSV + gitleaks).
5. [ ] `release.yml` dry-run via `workflow_dispatch` on the tag commit.
6. [ ] Asset names match the updater contract:
   `mycontrolpanel-macos-<version>.zip`,
   `mycontrolpanel-windows-<version>.zip`,
   `mycontrolpanel-linux-<version>.tar.gz`, `SHA256SUMS.txt`.
7. [ ] Linux clean-container check: deps list incl. `libsecret-1-dev` (#11).
8. [ ] macOS sandbox notes still true (entitlements, picker key import,
   deployment target) against current Xcode.
9. [ ] Tag notes = closed milestone issues summary, not a bare version bump:
   `git tag v<version> && git push origin v<version>`.
10. [ ] Post-release STATUS.md entry within 48h (what shipped, what slipped
    to the next milestone, risk movement).

## Escalation

Blocked > 3 days or a red checklist item the owner cannot clear alone goes
to the repo owner with: what, impact on milestone date, options (cut scope /
move milestone / accept risk). No silent milestone slips.
