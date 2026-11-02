# Deploy observability — Sentry release-health + dashboards

How we watch a release after it ships. App-side wiring: `ErrorReporting`
(release + environment on every opted-in event) and `ReleaseHealth`
(at most one heartbeat per install per 24 h) — both default-OFF with the
Sentry consent toggle, both incapable of breaking launch.

## What Sentry sees

| Field | Value | Source |
|---|---|---|
| `release` | `<package>@<version>+<build>` (e.g. `com.mycontrolpanel.my_control_panel@1.0.0-beta.1+1`) | `ErrorReporting.buildRelease` from `PackageInfo` at startup |
| `environment` | `beta` (pre-release tag builds), `production` (clean tag builds), `development` (local / PR / sideload) | `--dart-define=SENTRY_ENVIRONMENT` baked by `release.yml`; `resolveEnvironment` maps the rest |
| heartbeat | `MyControlPanel heartbeat` info message tagged `release` + `environment` | `ReleaseHealth.reportAppStart`, interval-gated in prefs |

CI registers each tag with Sentry (`Record Sentry release` step in the
publish job) so release-health starts tracking at publish time.

## Owner setup (Sofia)

- [ ] Create a Sentry project `mycontrolpanel` (Sentry cloud or self-hosted).
- [ ] Add `SENTRY_AUTH_TOKEN` (org auth token with `project:write`) and
      `SENTRY_ORG` (org slug) as secrets — either repo secrets or in both
      `release-beta` and `release-stable` environments. Until present, the
      CI record step skips silently and everything else keeps working.
- [ ] Share the Sentry DSN with beta users for the Settings opt-in
      (the DSN lives in each user's OS keychain, never in the repo).

## Dashboards (build once per project, filter per release)

1. **Crash-free sessions + users** (Sentry → Releases → Health): SLO
   **≥ 99.5% crash-free sessions and users over 7 days** on
   `environment:production`. Beta track (`environment:beta`) has no SLO —
   it is the canary; a beta regression blocks promotion, not a page.
2. **Rollout census** (Discover): `event.type:default
   message:"MyControlPanel heartbeat"` → count unique `release` per day,
   split by `environment`. Tells you which builds are alive in the field
   and when the old release drains to zero (the all-clear for the next
   promotion — see `docs/runbooks/rollout.md`).
3. **Adoption** (Releases → Adoption): 24 h / 14 d curves per release;
   a flat beta curve means the beta channel has no testers — recruit
   before promoting.
4. **Issues by release** (Issues → Release filter): new issues appearing
   only on the newest `release` = regression candidate → rollback per
   `docs/runbooks/rollout.md`, incident per `docs/runbooks/incident.md`.

## Alert routing (suggested)

| Signal | Threshold | Page? |
|---|---|---|
| Crash-free sessions (production) | < 99.5% over 1 h | Yes (incident runbook) |
| New issue on a beta release | any | No — comment on the rollout card, block promotion |
| Heartbeat census: beta installs | 0 for 48 h after publish | No — the beta has no testers; don't promote blind |
| Heartbeat census: old stable | > 5% of installs 14 d after stable | No — nudge update; keep the old assets published |

## Privacy notes (for the store listings)

- Reporting is opt-in, default OFF; the toggle + test-event live in
  Settings and the DSN never leaves the user's keychain.
- Heartbeats carry only release + environment tags — no host data, no
  server lists, no telemetry about monitored infrastructure.
- Environments keep dev noise (`development`) out of the production SLO.
