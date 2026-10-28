# Agent reliability review — :9108 metrics agent + systemd (Maisarah)

Companion to `agent-lifecycle.md` (install/operate) and `observability.md`
(alerting on top). This doc owns FAILURE MODES, VERSIONING, and ROLLOUT.
Facts checked 2026-10-28 against `AgentService.agentVersion` (= 4),
`agent_protocol.dart` (`kAgentProtocolVersion = 1`, `kMinAgentVersion = 2`),
`agent/mcp-agent.service`, and `scripts/install-agent.sh`.

## 1. Failure modes

| # | mode | symptom in app | detection | recovery |
|---|---|---|---|---|
| F1 | Agent process dead / host down | polls time out, server card goes stale | `AgentService` timeout → stale badge; `--check-only` from any checkout | `install-agent.sh` reinstall; unit has `Restart=always, RestartSec=5` so transient crashes self-heal — persistent death means the host, not the agent |
| F2 | Stale agent (`version` < 2, v1 payloads) | parse rejects, reinstall prompt | `kMinAgentVersion` floor in `agent_protocol.dart` (`/health` version missing/stale) | reinstall via script or one-click; old binary kept as `agent.py.bak.<UTC>` — `--rollback` restores newest backup |
| F3 | Token mismatch (v4 auth on, app holds old token) | 401 on every endpoint for that host | app surfaces auth failure distinctly from timeout (re-run install rotates BOTH sides together) | re-run install (mints + deploys + stores new token); manual path: `tee /etc/mcp-agent.env` + paste into Settings → key icon |
| F4 | systemd restart loop (bad agent.py upload) | flapping `/health`, version jitter | `systemctl status mcp-agent` + `journalctl -u mcp-agent`; sha256-skip in install script means a corrupt upload is never skipped silently | `--rollback`, then re-export `agentScript` from the app and reinstall |
| F5 | Port conflict (:9108 taken) | connection refused/reset while host is up | `curl 127.0.0.1:9108/health` on host; unit has no port guard by design (single canonical port) | free the squatter or move it — never run two agents; app has no port override |
| F6 | Token file unreadable (perms on `/etc/mcp-agent.env`) | agent starts OPEN (no `EnvironmentFile` = optional `-` prefix) while app sends token → 401-shaped confusion in reverse | `curl` without header returns 200 on a host that should be locked | `chmod 600 /etc/mcp-agent.env` + restart; treat any open-agent surprise as a finding, not a quirk |
| F7 | Clock/data anomalies (frozen uptime, flat KPIs) | metrics succeed but values never change | metrics-history p95/latency chart flatlines; log-tail shows agent alive | agent-side: restart unit; if it persists, the agent's `/proc` reads are broken for that kernel — file an issue with `/procstats` output |

Restart-loop guard today: `Restart=always` with 5s backoff and no burst
limit. Deliberate: the agent is stdlib-only and crash-looping on bad input
is a deploy bug (F4), not a runtime condition — bounding restarts would
mask it. Revisit if an agent ever does real parsing of untrusted input.

## 2. Versioning policy

Three numbers, three owners:

- Agent `version` field (currently **4**) — bumped when the wire payload
  gains a field. Owner: whoever changes `AgentService.agentScript`.
- `kAgentProtocolVersion` (= 1, app-side) — the contract the app speaks.
- `kMinAgentVersion` (= 2, app-side floor) — the oldest agent the app
  tolerates. v1 payloads (no `version` key) are rejected as stale.

Rules: new wire fields are OPTIONAL and ignored by old readers; the floor
only moves forward with a reinstall path tested (script + one-click +
manual command); `agentVersion` and the embedded `serviceUnit` ship in the
same app release so they can never skew.

## 3. Rollout plan (agent upgrades)

1. Ship the app release first — new app MUST still accept the oldest
   supported agent (`kMinAgentVersion`), so un-upgraded hosts keep working.
2. Upgrade agents host-by-host: `install-agent.sh --check-only` to list
   stale hosts, then reinstall per host (sha256-skip makes re-runs cheap).
3. Verify per host: `/health` version ≥ floor WITH the token header when
   auth is on; 401 without it.
4. Only after the fleet reports ≥ floor may a later release raise
   `kMinAgentVersion`. Never raise the floor in the same release that
   introduces the new agent version.
5. Rollback is per host (`--rollback` → newest `agent.py.bak.*`), never
   fleet-wide — hosts are independent.

## 4. Open items (not decided here)

- Burst-limit + `MemoryMax` on the unit: deferred per §F-note above.
- Fleet-wide version visibility (which hosts are stale) is a future
  control-center surface, not an agent change — needs the GitHub-API wave
  first (delivery plan Wave 1).
