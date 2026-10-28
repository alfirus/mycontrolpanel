# Agent lifecycle runbook (metrics agent :9108)

Canonical host layout (must match what the app's `AgentService.install`
and `manualInstallScript()` produce):

- Agent: `/opt/mcp-agent/agent.py` (stdlib-only Python, mode 644)
- Unit: `/etc/systemd/system/mcp-agent.service` (see `agent/mcp-agent.service`)
- Port: TCP `9108` (`/metrics`, `/procstats`), agent v2 contract

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
curl -s http://127.0.0.1:9108/metrics   # {"cpu":..,"ram":..,"disk":..,"uptime_days":..,"version":2}
curl -s http://127.0.0.1:9108/procstats # top processes + port table
```

- Upgrade: re-run the script (or app install) — old binary is kept as
  `agent.py.bak.<UTC timestamp>`; rollback restores the newest backup.
- Downgrade across agent versions: check `version` in `/metrics` matches
  what the app expects (`AgentService.agentVersion`, currently 2).
- Log tail + alerting on top of the agent: `docs/runbooks/observability.md`.

## Note on `agent/mcp-agent.service` vs the app-embedded unit

The app embeds a minimal unit so one-click install has no download step.
`agent/mcp-agent.service` is the hardened reference (network-online
ordering, `NoNewPrivileges`, `ProtectSystem=strict`). Keep the two
semantically in sync (same `ExecStart`, same paths); hardening-only
differences are intentional.
