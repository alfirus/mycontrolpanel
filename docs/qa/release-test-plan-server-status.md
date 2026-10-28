# Release Test Plan — Server Status + SSH / Agent Install

Owner: Balqis (QA Engineer) · Scope: `Server Status` segment + SSH connect +
one-click metrics-agent install (`:9108`) · App: MyControlPanel `1.0.0-alpha.1+1`
Code under test: `lib/services/agent_service.dart`, `lib/services/agent_protocol.dart`,
`lib/services/ssh_key_loader.dart`, `lib/screens/server_details_screen.dart`,
`lib/screens/control_center_screen.dart` (Server Status segment).

## 1. Entry / exit criteria

Entry: `flutter analyze` clean, `flutter test` green on the candidate commit,
agent script version pinned (`AgentService.agentVersion == 2`).
Exit (release GO): all P0 cases pass on every OS row of the matrix, no open
P0/P1 defects, install success rate 100% on password + key paths for Ubuntu
24.04 / Debian 12 targets.

## 2. OS matrix (client x target)

Client (app runs on): macOS 14+, Windows 11, Ubuntu 24.04, Android 14, iOS 17.
Target (SSH + agent): Ubuntu 24.04 (primary), Ubuntu 22.04, Debian 12.

| # | Client | Target | Auth | Expect |
|---|--------|--------|------|--------|
| M1 | macOS | Ubuntu 24.04 | password | connect + install + metrics in < 60s |
| M2 | macOS | Ubuntu 24.04 | key (picker import) | same; no path-typing (sandbox) |
| M3 | macOS | Debian 12 | key (pasted PEM) | same |
| M4 | Windows | Ubuntu 24.04 | password | same |
| M5 | Windows | Ubuntu 22.04 | key (picker import) | same |
| M6 | Linux | Ubuntu 24.04 | key (file content) | same |
| M7 | Linux | Debian 12 | password | same |
| M8 | Android | Ubuntu 24.04 | password | connect + metrics; install allowed |
| M9 | iOS | Ubuntu 24.04 | key (pasted PEM) | connect + metrics; install allowed |

Out of scope for this plan: agent on RHEL/Fedora/CentOS (no systemd-path
assumptions validated there yet) — tracked as a follow-up matrix row.

## 3. Server Status cases

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| SS-01 | Metrics populate after connect | Add server, open Server Details | CPU/RAM/DISK bars 0..1, sparkline, latency ms, uptime days |
| SS-02 | Stale-agent rejection | Point app at a v1 agent (`version: 1`) | `staleAgent` error, prompt to reinstall (see `agent_protocol_test.dart`) |
| SS-03 | Agent down / port closed | Stop `mcp-agent`, refresh | Status dot degrades, error surfaced, no crash, retry works after restart |
| SS-04 | Clamp out-of-range payload | (unit) cpu 9.9 / ram -1 | cpu 1.0, ram 0.0 (`parseAgentMetrics` clamp test) |
| SS-05 | Non-JSON / non-object body | (unit) `decodeAgentBody('not json')`, `'[1,2]'` | `badPayload` exception |
| SS-06 | HTTP 401 vs 404/500 mapping | (unit) `agentHttpError` | 401 → unauthorized; 404/500 → badPayload |
| SS-07 | Latency sanity | Compare app latency vs `ping` | Same order of magnitude; no negative/NaN display |
| SS-08 | Uptime accuracy | Compare uptime days vs `cat /proc/uptime` | Exact day count match |
| SS-09 | Multi-server overview | 3+ servers, mixed OS | Each card shows own metrics; failed host does not blank others |
| SS-10 | Refresh storm | Pull-to-refresh 5x in 10s | No overlapping-poll crash, latest values win |

## 4. SSH auth cases (password vs key)

| ID | Case | Expected |
|----|------|----------|
| AU-01 | Password auth happy path | Connected; wrong password → clear auth-failure message |
| AU-02 | Key via picker import | Content stored (never path); connect OK (macOS sandbox-safe) |
| AU-03 | Pasted PEM content | Connect OK; trailing-whitespace PEM still loads |
| AU-04 | Encrypted key, no passphrase | `SSH_KEY_NEEDS_PASSPHRASE`, UI prompts, no hang |
| AU-05 | Encrypted key + passphrase | Unlocks and connects |
| AU-06 | Unloadable key | `SSH_KEY_AUTH` → guided manual install fallback offered |
| AU-07 | Non-standard SSH port | Custom port respected for SSH and `:9108` verify |
| AU-08 | Host unreachable / timeout | 10s SSH timeout surfaces readable error, no indefinite spinner |

## 5. Agent install (systemd unit) cases

Install path: stdlib-only Python → `/opt/mcp-agent/agent.py` + unit
`mcp-agent.service` (`After=network.target`, `Restart=always`, `RestartSec=5`),
verify `GET http://host:9108/metrics`.

| ID | Case | Expected |
|----|------|----------|
| IN-01 | Password install (Ubuntu 24.04) | Unit active, `/metrics` returns v2 JSON |
| IN-02 | Key install (Debian 12) | Same as IN-01 |
| IN-03 | Reinstall over existing agent | Idempotent; old unit replaced, metrics resume |
| IN-04 | `/procstats` shape | `version: 2`, `top[]` with pid/name/cpu/mem_mb, `ports{}` map |
| IN-05 | Missing python3 on target | Clear error log line, install marked failed, manual steps shown |
| IN-06 | No sudo / non-root SSH user | Passwordless-sudo attempted, graceful manual-install fallback |
| IN-07 | Port 9108 already taken | Verify step fails with readable message, no silent wrong-metrics |
| IN-08 | Reboot persistence | `Restart=always`: metrics return after target reboot without reinstall |
| IN-09 | Firewall note | Log line records "no local firewall rule applied" as non-fatal |

## 6. Defect severity guide

P0 (block release): cannot connect, install fails on matrix primary rows,
metrics blank/crash, wrong clamp (values outside 0..1 displayed).
P1: misleading error text, retry broken, single-OS-row failure.
P2: log noise, cosmetic status-dot lag. P3: doc wording.

Defects are filed as repo issues with repro steps (host OS, target OS, auth
method, app commit, agent version, logs) — never as chat messages.
