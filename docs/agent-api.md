# Metrics Agent API Reference (`:9108`)

The app reads live server metrics from a tiny **stdlib-only Python agent**
installed on each monitored host. The agent serves plain HTTP on fixed TCP
port **9108** and has two endpoints. No dependencies beyond Python 3 itself.

Source of truth for the implementation: `AgentService.agentScript`
in `lib/services/agent_service.dart` (agent v2). The normative wire
contract (validators, version negotiation) is specified in
`docs/specs/agent-protocol.md` — currently in review as PR #37; this page
is the human-readable reference and defers to that spec on conflicts.

## Base URL

```text
http://<host>:9108
```

- Binds `0.0.0.0:9108` on the monitored host. No TLS, no auth on the wire
  (agent v2 serves unauthenticated HTTP by design — stdlib-only constraint).
- Client timeouts: connect **5s**, `/metrics` read **6s**, `/procstats`
  read **8s**.
- Restrict exposure with a host firewall (`ufw` / `firewalld`, opened by
  the installer) **and** a cloud security group on public hosts. The repo
  is public — never assume `:9108` is unreachable from the internet.
- Reserved header `X-MCP-Agent-Token`: clients send it when a per-host
  agent token is configured (Settings → server entry). Agent v2 ignores it;
  it is reserved so the agent can start enforcing `401` later without an
  app update.

## GET /metrics

Returns the host's current CPU / RAM / disk load plus uptime.

```bash
curl -s http://192.168.1.10:9108/metrics
```

```json
{"cpu": 0.12, "ram": 0.63, "disk": 0.41, "uptime_days": 17, "version": 2}
```

| Field         | Type   | Rule                                   |
|---------------|--------|----------------------------------------|
| `cpu`         | number | CPU utilisation ratio, 0–1 (client clamps out-of-range values) |
| `ram`         | number | RAM utilisation ratio, 0–1             |
| `disk`        | number | Root-filesystem utilisation ratio, 0–1 |
| `uptime_days` | int    | Whole days since boot, ≥ 0             |
| `version`     | int    | Agent software version, **required** (currently `2`) |

How each value is measured (Linux, `/proc`-based):

- `cpu`: 1 − (idle-delta / total-delta) sampled over 0.5s from
  `/proc/stat`; falls back to `os.getloadavg()[0]` (clamped to 0–1).
- `ram`: 1 − (`MemAvailable` / `MemTotal`) from `/proc/meminfo`
  (falls back to `MemFree`).
- `disk`: 1 − (free / total) from `os.statvfs('/')`.
- `uptime_days`: `/proc/uptime` integer-divided by 86400.

## GET /procstats (agent v2+ only)

APM-lite: top processes by CPU plus per-port connection state. Surfaced in
the Apps tab and Server Details screen.

```bash
curl -s http://192.168.1.10:9108/procstats
```

```json
{
  "version": 2,
  "top": [{"pid": 1, "name": "systemd", "cpu": 0.002, "mem_mb": 12}],
  "ports": {"3000": {"listening": true, "established": 2}}
}
```

| Field              | Type        | Rule                                                        |
|--------------------|-------------|-------------------------------------------------------------|
| `version`          | int         | Agent software version, **required**                        |
| `top`              | array ≤ 12  | Sorted by `cpu` desc; per entry `pid` int, `name` string, `cpu` 0–1, `mem_mb` ≥ 0 |
| `ports.<port>`     | object      | Key is the decimal port string; `listening` bool, `established` int ≥ 0 |

Measurement notes:

- `top`: two `/proc/<pid>/stat` snapshots (utime+stime) 0.5s apart,
  normalised by total CPU delta; VmRSS from `/proc/<pid>/status`
  (reported in MiB). Capped at the 12 hottest processes.
- `ports`: parsed from `/proc/net/tcp` and `/proc/net/tcp6`
  (`0A` = listening, `01` = established).

Any other path returns **404** with an empty body.

## Version negotiation

- The app implements protocol v1 and accepts agent software `version >= 2`.
- A payload with **no** `version` key is an agent v1 install: the client
  must treat it as `staleAgent` (prompt reinstall), **not** as a generic
  parse error.
- Unknown future `version > 2`: accept while all required fields validate;
  ignore unknown extra fields (forward-compatible reads).

## Errors (client-side taxonomy)

`AgentService.fetch` / `fetchAppStats` return `null` on any failure (legacy
behaviour); new code paths surface typed errors per the protocol spec:

| Code           | Trigger                                        | What the UI does                                  |
|----------------|------------------------------------------------|---------------------------------------------------|
| `unreachable`  | TCP refused, DNS failure, host down            | Status dot grey + "agent unreachable"             |
| `timeout`      | No full response within the read budget        | Keep last metrics, mark stale                     |
| `badPayload`   | Non-200 (except 401), non-JSON, schema violation | "agent returned garbage — reinstall?"           |
| `staleAgent`   | Missing `version`, or `< 2`                    | Reinstall banner (one-click or manual)            |
| `unauthorized` | HTTP 401 (reserved for future token enforcement) | Prompt for the agent token                      |

Every successful `/metrics` poll appends one point to the per-host
`MetricsHistory` ring buffer (capped at 120 points); failures record
nothing.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `curl` hangs, then connection timeout | TCP 9108 blocked | Open the port: `sudo ufw allow 9108/tcp` (or `firewall-cmd`), plus the cloud security group |
| Connection refused | Agent not running | `sudo systemctl status mcp-agent`; restart with `sudo systemctl restart mcp-agent` |
| 404 on `/metrics` | Wrong path or stale agent | Reinstall via the app's one-click installer; see [Setup guide](setup.md) |
| `staleAgent` / missing `version` | Agent v1 still installed | Reinstall (v1 payloads carry no `version` key) |
| Values stuck / stale in the app | Poll failures keep last-known metrics | Check the agent from the app host: `curl -s http://<host>:9108/metrics` |
