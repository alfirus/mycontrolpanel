# Agent lifecycle runbook (metrics agent :9108)

Canonical host layout (must match what the app's `AgentService.install`
and `manualInstallScript()` produce):

- Agent: `/opt/mcp-agent/agent.py` (stdlib-only Python, mode 644)
- Unit: `/etc/systemd/system/mcp-agent.service` (see `agent/mcp-agent.service`)
- Port: TCP `9108` (`/health`, `/metrics`, `/procstats`), agent v4 contract

## Option A — scripted (idempotent)

From a checkout of this repo:

```sh
# install or upgrade (skips upload when sha256 matches, backs up otherwise)
scripts/install-agent.sh --host example.com --user deploy --identity ~/.ssh/id_ed25519 --agent-file /tmp/agent.py

# health check only (no changes, safe for cron/monitoring)
scripts/install-agent.sh --host example.com --user deploy --check-only

# rollback to the newest /opt/mcp-agent/agent.py.bak.* on the host
scripts/install-agent.sh --host example.com --user deploy --rollback
```

`--agent-file` defaults to `agent/agent.py` (not checked in — export it
from the app's guided install screen, which embeds `AgentService.agentScript`).
Exit codes: `0` ok · `1` usage/ssh/scp · `2` health check failed · `3` sudo missing.

## Option B — one-click / manual (from the app)

Same result, driven from the UI: the app uploads `agentScript` + its
embedded `serviceUnit` over the saved SSH connection, enables the unit,
opens the firewall (best-effort) and verifies `/metrics` from the phone.
If the server user lacks passwordless sudo, use the app's manual-install
command (single line, paste into the server's own terminal).

## Privileged host steps (manual, need server root — never in CI)

```sh
# passwordless sudo for the deploy user (one-click + script need `sudo -n`)
echo "deploy ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/deploy

# after editing the unit by hand
sudo systemctl daemon-reload && sudo systemctl enable --now mcp-agent

# firewall (whichever the host uses) + cloud security group for TCP 9108
sudo ufw allow 9108/tcp
```

## Operate

```sh
systemctl status mcp-agent
journalctl -u mcp-agent -n 100 --no-pager
curl -s http://127.0.0.1:9108/health    # {"status":"ok","version":4,...}
curl -s http://127.0.0.1:9108/metrics   # {"cpu":..,"ram":..,"disk":..,"uptime_days":..,"version":4}
curl -s http://127.0.0.1:9108/procstats # top processes + port table
```

## Token auth (v4+, opt-in)

```sh
# server side — the app sends this value as X-MCP-Agent-Token
echo 'MCP_AGENT_TOKEN=<long-random>' | sudo tee /etc/mcp-agent.env
sudo chmod 600 /etc/mcp-agent.env && sudo systemctl restart mcp-agent

# verify: 401 without the header, 200 with it
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9108/health
curl -s -H 'X-MCP-Agent-Token: <long-random>' http://127.0.0.1:9108/health
```

Unset/absent `/etc/mcp-agent.env` = open agent (v2/v3-compatible).

One-click install (app) now provisions the token automatically: it mints a
256-bit secret, deploys it as `/etc/mcp-agent.env` (mode 600) via the same
SSH session, and stores the identical value in the OS keychain
(`SecureStore`, key `agent_tok:<serverId>`) — polling sends it as
`X-MCP-Agent-Token` on every metrics/procstats/health/logs call, and the
install-verify step authenticates with it. Re-running install rotates the
token on BOTH sides together. Manual/script installs: set the host side per
the block above, then paste the same value into the app via Settings →
server row → key icon (value hidden after save; CLEAR reverts that host to
open polling). Deleting a server wipes its keychain token too.

- Upgrade: re-run the script (or app install) — old binary is kept as
  `agent.py.bak.<UTC timestamp>`; rollback restores the newest backup.
- Downgrade across agent versions: check `version` in `/metrics` matches
  what the app expects (`AgentService.agentVersion`, currently 4).
- Log tail + alerting on top of the agent: `docs/runbooks/observability.md`.

## Note on `agent/mcp-agent.service` vs the app-embedded unit

The app embeds a minimal unit so one-click install has no download step.
`agent/mcp-agent.service` is the hardened reference (network-online
ordering, `NoNewPrivileges`, `ProtectSystem=strict`). Keep the two
semantically in sync (same `ExecStart`, same paths); hardening-only
differences are intentional.
