# Ops runbooks + health checks (agent :9108 / systemd)

Start here when something is red. Area deep-dives live in
[`docs/runbooks/`](runbooks/): `agent-lifecycle.md` (install/upgrade),
`agent-reliability.md` (failure modes), `observability.md` (polling,
log tail, SLOs), `secrets-hardening.md` (tokens, keychain).

Conventions: the agent is stdlib-only Python at
`/opt/mcp-agent/agent.py`, run by `systemd` as `mcp-agent.service`,
serving HTTP on TCP `9108`. The app's copy of the agent source is
`AgentService.agentScript` (v5 adds `GET /cronruns`); reinstalling from
the app always deploys the current version.

## 30-second health check

Run on the host (or adapt with `ssh user@host -- …`):

```sh
systemctl is-active mcp-agent            # expect: active
curl -s -m 5 http://127.0.0.1:9108/health  # expect: {"status":"ok","version":5,...}
curl -s -m 5 http://127.0.0.1:9108/metrics # expect: {"cpu":..,"ram":..,"disk":..,...}
```

From this machine (no SSH session needed):

```sh
scripts/install-agent.sh --host example.com --user deploy --check-only
# exit 0 = healthy, exit 2 = agent answered badly, exit 3 = sudo missing
```

## Failure matrix

| Symptom | Diagnose | Fix |
|---|---|---|
| App: agent unreachable (metrics blank) | `systemctl status mcp-agent`; `ss -ltnp \| grep 9108` | `sudo systemctl restart mcp-agent`; if the port is held by another process, stop the squatter or move it — the agent port is fixed (R8 gate pins `9108` in the agent payload) |
| Unit in `failed` state, restart loop | `journalctl -u mcp-agent -n 50 --no-pager` (usually a Python traceback) | Fix the cause, then `sudo systemctl reset-failed mcp-agent && sudo systemctl start mcp-agent`. Recurring after reboot = enable it: `sudo systemctl enable mcp-agent` |
| `/health` 401 (app shows auth error) | Host enforces token auth but the app sends the wrong/missing token | Rotate together: reinstall from the app (mints + stores a new token on both sides) or set `/etc/mcp-agent.env` manually and mirror the value into Settings → token for that host, then `sudo systemctl restart mcp-agent` |
| App warns "stale agent" | `curl -s …/health` shows `"version": 1` or no `version` key | Reinstall from the app (one click) or `scripts/install-agent.sh --host …` — old agents predate the version contract |
| `/cronruns` 404, Cronjobs show SCHEDULED only | Agent is v4 or older (endpoint is v5+) | Reinstall to v5; until then the app serves its last-good cache. Jobs must also opt into the log (see below) |
| Cronjobs show no history on a v5 agent | `ls -l /var/log/mcp-cronruns.log` — jobs never opted in | Append one line per run from each job: `echo "$(date +%s) <name> <exit> [dur_s]" >> /var/log/mcp-cronruns.log`. Ensure the cron user can write the file (`touch` it once, `chown` to the job user) |
| Deployments timeline stale / "cached • retrying" | GitHub rate limit or token scope; subtitle says which repos failed | Wait out the backoff (5m doubling to 1h per repo) or hit SYNC to force a live retry; check token has `repo` scope in Settings → GitHub |
| Alerts stop updating but metrics flow | SSH sweep failing (key rotated, `sudo -n` lost) while agent HTTP still answers | Re-add the key in Settings → server, confirm `sudo -n true` on the host; the agent leg (disk/load) keeps covering while SSH is down |
| Install fails: `SUDO_NEED_PASS` | Target user lacks passwordless sudo | `echo "USER ALL=(ALL) NOPASSWD:ALL" \| sudo tee /etc/sudoers.d/USER` (needs server root), or use the manual install command from the app |

## Restart vs reinstall

- **Restart** (`sudo systemctl restart mcp-agent`) — first move for a
  wedged/dead agent. Zero config change, 5s back.
- **Reinstall** (app one-click or `install-agent.sh --host …`) — for stale
  versions, corrupted `/opt/mcp-agent/agent.py`, or token rotation. The
  script skips the upload when sha256 matches and backs up otherwise;
  `--rollback` restores the newest `/opt/mcp-agent/agent.py.bak.*`.
- **Manual** (paste the app's single-line command on the host) — when the
  deploy user has no passwordless sudo and you have the root password.

## Token rotation (no outage)

1. Reinstall from the app — it mints a 256-bit token, writes
   `/etc/mcp-agent.env` (mode 600) over the same SSH session, and stores
   the identical value in the OS keychain. Both sides change atomically.
2. Manual path: write the new secret to `/etc/mcp-agent.env`, mirror it
   into the app's per-host token, then restart the unit. Between steps
   the agent answers 401 — do both within one maintenance window.

## What NOT to do

- Never hand-edit `/opt/mcp-agent/agent.py` on the host — the next
  reinstall overwrites it and the drift is invisible. Change
  `AgentService.agentScript` in the repo and reinstall.
- Never commit tokens, PEMs, or `/etc/mcp-agent.env` contents. The repo
  is public; CI runs gitleaks on every PR.
- Never open `9108` to the internet without token auth set. Bind or
  firewall it to the monitoring host (see `agent-lifecycle.md`).

## Escalation

Needs server root (not doable from the app): passwordless-sudo grants,
firewall/security-group changes, unit edits, log-file ownership. Needs
owner sign-off: license/packaging calls, release tags, anything outside
this file — park it in a `need-owner-decision` card, don't improvise.
