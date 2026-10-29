# Proposal template — MyControlPanel engagement

Copy this file per prospect, fill every `{{bracket}}`, delete these
instructions before sending. Nothing here quotes a price or SLA — there are
none to quote until Sofia + Finance sign PR #28 (see `docs/packaging.md`).

---

## 1. Cover

**To:** {{prospect_name}} ({{prospect_company}})
**From:** Syafiqah, Sales Manager @ MyControlPanel
**Date:** {{date}} | **Valid through:** {{valid_through}}
**Subject:** MyControlPanel Community pilot — {{scope_one_liner}}

## 2. Understanding (their words)

- Fleet today: {{fleet_size}} boxes ({{os_mix}}), managed via {{current_tooling}}.
- Pain: {{pain_1}}; {{pain_2}}.
- Success looks like: {{success_criteria}}.

## 3. Scope — what we will do

| Week | Activity | Owner | Done means |
|---|---|---|---|
| 1 | Install Community edition on {{seats}} machines; connect {{pilot_hosts}} pilot hosts | Joint | Overview grid live on real hosts |
| 1–2 | One-click metrics-agent install per pilot host (`:9108`, stdlib-only Python) | Joint | Live metrics + p95 chart per host |
| 2 | Cron discovery review + per-job log walkthrough | Syafiqah + {{poc}} | Every crontab accounted for |
| 2–3 | Alert tuning (disk ≥80/90%, failed units, brute-force, load, kernel, reboots) | Joint | Badge + snack verified on a real signal |
| 3 | Terminal + AI-chat walkthrough (bring-your-own key or local Ollama) | Syafiqah | POC runs a session unaided |

Out of scope (say so upfront): background polling/push while closed, biometric
lock enforcement, Sentry/Datadog integrations, GitHub / CI-CD timeline /
Security-findings API wiring (UI-ready, roadmap — GitLab equivalent is live).

## 4. Deployment

- Client app only — macOS / Windows / Linux / iOS / Android from one codebase;
  no server-side stack beyond the per-host metrics agent (one-click SSH install,
  verified `GET /metrics`, uninstall = remove the systemd unit + close `:9108`).
- No data leaves the device except the SSH sessions the customer configures;
  no telemetry, no vendor cloud, no account required.
- AI chat: customer's own provider key or self-hosted Ollama; audit trail is
  append-only, capped at 200, viewable in the chat drawer.

## 5. Security FAQ (confirmed against `docs/runbooks/secrets-hardening.md`)

| Question | Answer (do not improvise beyond this) |
|---|---|
| Where do my server passwords / keys / tokens live? | In the OS keychain/keystore via `SecureStore` (`flutter_secure_storage`). Prefs hold only `secure:srv_cred_<id>` markers — never raw material. |
| What about SSH private keys? | Imported via file picker or pasted as PEM content; key *material* is stored only through `SecureStore`, never as a path. Encrypted-key passphrase is asked once per visit. |
| Per-host agent tokens? | Auto-provisioned by one-click install into `SecureStore` (`agent_tok:<id>`); set/rotate/clear from the Settings key icon; wiped on server delete; never displayed. |
| Host-key verification? | TOFU-pinned `SHA256:...` fingerprints per host:port. First connect pins + reports "new host key pinned" (verify out-of-band via `ssh-keygen -lf` on the server); later mismatch = connection REFUSED fail-closed. |
| Do secrets leak into logs? | Map entries pass through `SecretHygiene.redactForLog` before logging; `describe` returns only non-secret fingerprints (e.g. "OPENSSH PRIVATE KEY, encrypted"). |
| Repo/CI hygiene? | `security.yml` runs gitleaks on every PR (public repo, zero tolerance); osv-scan on `pubspec.lock`; signing credentials stay owner-held and manual per `docs/release-process.md`. |
| Anything you can't claim? | No SOC 2 / ISO certs, no pen-test report, no SSO/audit-export (Pro candidates, not built). Offer the runbook + code paths, never a certificate we don't hold. |

## 6. Commercials

MyControlPanel Community is MIT-licensed and free — this pilot has no license
fee to quote. Any paid Pro/MSP terms are undecided (PR #28, owner call); do not
fill numbers here. If the prospect asks, log the interest for post-v1 and move on.

| Item | Terms |
|---|---|
| License | MIT (`LICENSE`), unlimited servers |
| Pilot effort | {{effort_statement}} (time-boxed above; no SLA implied) |
| Support during pilot | {{support_statement}} (community + sales-manager attention; no SLA) |

## 7. Acceptance + next steps

1. {{poc}} confirms the Overview grid is live on {{pilot_hosts}} pilot hosts.
2. Joint sign-off that every crontab is discovered with per-job logs openable.
3. Alert badge + snack demonstrated on a real firing signal.
4. Go / no-go on wider rollout recorded in the pipeline file; paid-interest (if
   any) logged for post-v1 follow-up.

Questions on messaging → Naura (CMO). Technical depth → via Sofia to
Maisarah's team. Source of truth for every claim above:
README real-vs-roadmap matrix + `docs/runbooks/secrets-hardening.md`.
