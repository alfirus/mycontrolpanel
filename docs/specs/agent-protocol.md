# Agent Protocol v1 — :9108 JSON contract

Status: **normative** for app releases reading agent software v2+.
Code counterpart: `lib/services/agent_protocol.dart`
(transport stays in `lib/services/agent_service.dart`).

## 1. Transport

- Plain HTTP on fixed TCP **9108** (`kAgentPort`). No TLS on the wire:
  the agent binds `0.0.0.0:9108` and is expected to run behind host-local
  firewall rules (ufw / firewalld, opened by the installer) or a trusted LAN.
  The repo is **public** — never assume the agent port is unreachable from
  the internet; operators MUST restrict it with a cloud security group.
- Client timeouts: connect **5s**, `/metrics` read **6s**,
  `/procstats` read **8s**.

## 2. Endpoints

### GET /health → 200 application/json (agent v4+)

```json
{"status": "ok", "version": 4, "agent_uptime_s": 123}
```

| field | type | rule |
|---|---|---|
| `status` | string | always `"ok"` on a live agent |
| `version` | int | agent software version; **required** |
| `agent_uptime_s` | int | seconds since the agent process started; ≥ 0 |

Cheap by design — no `/proc` scan. Hit this first from install-verify,
Zara's polling job, and any load-balancer check; only fall through to
`/metrics` when the host is confirmed alive.

### GET /metrics → 200 application/json

```json
{"cpu": 0.0, "ram": 0.0, "disk": 0.0, "uptime_days": 0, "version": 2}
```

| field | type | rule |
|---|---|---|
| `cpu` / `ram` / `disk` | number | ratio 0..1 (client clamps) |
| `uptime_days` | int | ≥ 0 |
| `version` | int | agent software version; **required** |

### GET /procstats → 200 application/json (agent v2+ only)

```json
{
  "version": 2,
  "top": [{"pid": 1, "name": "systemd", "cpu": 0.0, "mem_mb": 12}],
  "ports": {"3000": {"listening": true, "established": 2}}
}
```

| field | type | rule |
|---|---|---|
| `top` | array ≤ 12 | sorted by `cpu` desc; `cpu` 0..1, `mem_mb` ≥ 0 |
| `ports.<port>` | object | `listening` bool, `established` int ≥ 0; keys are decimal port strings |

Any other path → **404** with a JSON body (`{"error":"not_found",...}`).
Non-GET methods → **405** (`{"error":"method_not_allowed",...}`).
Bad `/logs` source → **400** (`{"error":"bad_source","allowed":[...]}`).

### GET /logs → 200 application/json (agent v4+)

```json
{"version": 4, "source": "journal", "lines": ["Oct 28 sshd[1]: ..."]}
```

| field | type | rule |
|---|---|---|
| `source` | string | `journal` or `syslog` (allowlisted; anything else → 400) |
| `lines` | array ≤ 500 | newest last, blank lines stripped |
| query | `?source=&lines=` | `lines` clamped 20..500, defaults 100 |

Read-only by construction: no shell (argv exec of `journalctl` only),
no arbitrary paths (fixed syslog fallbacks). Token-gated like every
other endpoint when `MCP_AGENT_TOKEN` is set.

### GET /sysstats (agent v3+) — see `docs/specs/agent-sysstats.md`

v4 adds two additive keys: `nproc` (CPU count, for load-vs-capacity
checks without SSH) and `boot_epoch_s` (unix epoch of last boot, for
reboot detection from Zara's polling job). Older validators ignore
unknown keys.

### GET /cronruns → 200 application/json (agent v5+)

Agent-side cron run log for the last-run tracker. Jobs opt in by
appending one line per run:

```sh
echo "$(date +%s) backup 0 12" >> /var/log/mcp-cronruns.log
# fields: <epoch_s> <name> <exit> [dur_s]
```

```json
{"version": 5, "runs": [{"at": 1793085600, "name": "backup", "exit": 0, "dur_s": 12}]}
```

| field | type | rule |
|---|---|---|
| `runs` | array ≤ 200 | newest first; garbage lines skipped server-side |
| `runs[].at` | int | unix epoch **seconds** of the run |
| `runs[].name` | string ≤ 80 | program name (matched client-side to the cron's program) |
| `runs[].exit` | int | process exit code (`0` = ok) |
| `runs[].dur_s` | int? | duration in seconds; absent when the job does not report it |
| query | `?lines=` | rows returned, clamped 1..200, defaults 50 |

Missing/empty log file → `200` with `"runs": []` (never an error, so
older setups without the logging convention simply show no history).
Pre-v5 agents answer **404** → the app falls back to its last-good cache.
Token-gated like every other endpoint when `MCP_AGENT_TOKEN` is set.

## 3. Version negotiation

- App implements protocol v1 (`kAgentProtocolVersion = 1`).
- App accepts agent software `version >= 2` (`kMinAgentVersion`).
- Agent v1 payloads carry **no** `version` key → client MUST treat a
  missing `version` as `staleAgent`, **not** as a generic parse error,
  and prompt reinstall (one-click installer or manual script).
- Unknown future `version > 2`: accept while all required fields validate;
  ignore unknown extra fields (forward-compatible reads).

## 4. Auth

Agent v2/v3 serve **unauthenticated** HTTP (stdlib-only constraint).
Agent **v4+ enforces an optional shared-secret token**:

1. Operator sets `MCP_AGENT_TOKEN` via `/etc/mcp-agent.env`
   (`EnvironmentFile=-/etc/mcp-agent.env` in the systemd unit; mode 600).
2. When the variable is **set**, every endpoint (including `/health`)
   requires the `X-MCP-Agent-Token` header with a constant-time compare;
   mismatch or absence → **401** with a JSON body
   (`{"error":"unauthorized",...}`).
3. When the variable is **unset**, the agent stays open — fully backwards
   compatible with v2/v3 clients and with existing hosts that never opt in.
4. Clients MUST send the header whenever a per-host agent token is
   configured (Settings → server entry); v2/v3 agents ignore unknown
   headers, so rollout needs no app update on either side.
5. Future 401 → typed `unauthorized` error (already in the taxonomy).

Keep the mitigations below in force regardless: firewall the port,
never assume it is unreachable from the internet on a public repo.

1. Bind scope: installer opens 9108 only on host firewalls the operator
   controls; public-cloud hosts MUST add a security-group rule.
2. Reserved token header `X-MCP-Agent-Token`: clients MUST send it when a
   per-host agent token is configured (Settings → server entry); v2 agents
   ignore it, so rollout needs no app update when the agent starts
   enforcing 401.
3. Future 401 → typed `unauthorized` error (already in the taxonomy).

## 5. Error taxonomy (client-side)

| code | trigger | UI mapping |
|---|---|---|
| `unreachable` | TCP refused / DNS / host down | status dot grey + "agent unreachable" |
| `timeout` | no full response in read budget | keep last metrics, mark stale |
| `badPayload` | non-200 (except 401), non-JSON, schema violation | "agent returned garbage — reinstall?" |
| `staleAgent` | missing `version` or `< 2` | reinstall banner |
| `unauthorized` | HTTP 401 (reserved) | prompt for agent token |

Rules:

- Pollers MUST surface typed `AgentProtocolException`, never bare `null`
  on new code paths. (Legacy `AgentService.fetch`/`fetchAppStats` return
  `null` on any failure — downstream keeps null-tolerance until the
  service-layer split migrates them; see `docs/specs/service-layer.md`.)
- Every successful `/metrics` poll appends one point via `MetricsHistory`
  (cap 120/host); failures record nothing.
- Install-verify (`AgentService.install` tail + manual-script VERIFY) polls
  `/metrics` per the §1 budget and reports `staleAgent` distinctly from
  `unreachable` so firewall vs. old-agent confusion ends.

## 6. Coverage map (this spec governs)

- Agent install script: `AgentService.agentScript` (v4 Python) +
  `serviceUnit` (systemd) + `manualInstallScript()`.
- Metrics reads: `AgentService.fetch` (:9108 `/metrics`),
  `fetchAppStats` (:9108 `/procstats`), `fetchHealth` (:9108 `/health`),
  `MetricsHistory.record`/`p95`.
- Out of scope: SSH discovery (cron/apps/alerts/log-tail) — transport is
  SSH, not HTTP; covered by the service-layer split instead.
