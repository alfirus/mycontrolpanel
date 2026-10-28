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

Any other path → **404** with empty body.

## 3. Version negotiation

- App implements protocol v1 (`kAgentProtocolVersion = 1`).
- App accepts agent software `version >= 2` (`kMinAgentVersion`).
- Agent v1 payloads carry **no** `version` key → client MUST treat a
  missing `version` as `staleAgent`, **not** as a generic parse error,
  and prompt reinstall (one-click installer or manual script).
- Unknown future `version > 2`: accept while all required fields validate;
  ignore unknown extra fields (forward-compatible reads).

## 4. Auth

Agent v2 serves **unauthenticated** HTTP (stdlib-only constraint).
Mitigations, in priority order:

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

- Agent install script: `AgentService.agentScript` (v2 Python) +
  `serviceUnit` (systemd) + `manualInstallScript()`.
- Metrics reads: `AgentService.fetch` (:9108 `/metrics`),
  `fetchAppStats` (:9108 `/procstats`), `MetricsHistory.record`/`p95`.
- Out of scope: SSH discovery (cron/apps/alerts/log-tail) — transport is
  SSH, not HTTP; covered by the service-layer split instead.
