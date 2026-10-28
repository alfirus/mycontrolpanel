# Read-only access runbook (restricted `monitor` account)

Two separate guarantees, don't conflate them:

- **The app only reads** — a design promise (AI tools are allowlisted to
  `systemctl status`, `journalctl` reads, `df`/`uptime`/`free`, log greps;
  see `lib/services/ai_tools.dart`).
- **The account cannot write** — an OS-enforced boundary. This runbook.
  Even if the app (or its AI) asked for a write, the server refuses it.

## 1. Create the restricted user

Run on the server as root (or a privileged admin — **not** the account
you are about to create). The one-click agent installer needs passwordless
sudo, so do the install with your admin account **first**, then hand the
app the `monitor` credentials.

```sh
sudo useradd -m -s /bin/bash monitor   # functional shell: SSH collectors work
sudo passwd -l monitor                 # lock password auth: keys only
sudo -u monitor mkdir -p -m 700 /home/monitor/.ssh
echo 'ssh-ed25519 AAAA...your-app-key...' | sudo -u monitor tee /home/monitor/.ssh/authorized_keys >/dev/null
sudo chmod 600 /home/monitor/.ssh/authorized_keys
```

Confirm the account has no sudo:

```sh
sudo -l -U monitor   # expect: "User monitor is not allowed to run sudo" (or no entries)
```

Harden `sshd` for this user (in `/etc/ssh/sshd_config`, then
`sudo systemctl reload sshd`):

```
Match User monitor
    PasswordAuthentication no
    AllowAgentForwarding no
    AllowTcpForwarding no
    X11Forwarding no
```

> **Agent-only maximum lockdown:** if you only want metrics (CPU/RAM/disk
> from `:9108`, which needs no SSH at all), create the user with
> `-s /usr/sbin/nologin` instead. SSH exec then fails closed
> ("This account is currently not available") while the agent leg keeps
> reporting. Everything in §2 marked "SSH collector" goes dark in this
> mode — that is the point. (`rssh`-style shells are the same idea;
> `nologin` ships with every distro, so prefer it.)

## 2. What the app needs from this account

Baseline — works with **zero sudo** (every collector below degrades to
`2>/dev/null` fallbacks instead of failing when elevation is missing):

| Collector | Command the app runs | Needs |
|---|---|---|
| Metrics | `GET http://<host>:9108/metrics` (direct HTTP, no SSH) | agent installed + token in the app |
| Cronjobs | `crontab -l`, `cat /etc/crontab`, `cat /etc/cron.d/*` | world-readable on stock distros |
| Apps | `systemctl list-units --type=service --state=running`, `ss -ltn` | unprivileged listing works |
| Alerts | `systemctl list-units --state=failed`, `df`, `uptime` | unprivileged |
| Log tail | `journalctl --no-pager --since ...` | own-user journal only without elevation |

Full fidelity for two collectors needs log access. Prefer **group
membership** (no sudo involved) over sudoers:

```sh
sudo usermod -aG systemd-journal,adm monitor   # system journal + /var/log reads
sudo usermod -aG docker monitor                # only if you want container names in Apps
```

A **narrow sudoers allowlist** is the last resort — only if a collector
truly needs it and groups are not an option. Example (brute-force SSH
counts), and nothing else:

```
monitor ALL=(ALL) NOPASSWD: /bin/journalctl --no-pager -u ssh *, /bin/journalctl --no-pager -u sshd *
```

Never grant `monitor ALL=(ALL) NOPASSWD:ALL`, never reuse your deploy or
root account for the app connection, and never open agent port `9108` to
the internet without token auth (token in `/etc/mcp-agent.env`, mode 600,
mirrored in the app's keychain — see `secrets-hardening.md`).

## 3. Revoke access (two commands)

Remove the key (kills app access immediately, account stays for audit):

```sh
sudo rm -f /home/monitor/.ssh/authorized_keys
```

Delete the account (after key removal, when you are done investigating):

```sh
sudo userdel -r monitor
```

Verify access is gone — all three must fail:

```sh
ssh -o BatchMode=yes -o ConnectTimeout=5 monitor@<host> true  # expect: exit 255, "Permission denied"
id monitor                                                     # expect: "no such user" (after userdel)
curl -s -m 5 http://<host>:9108/metrics -H "Authorization: Bearer <old-token>"  # expect: 401 after rotation
```

Then rotate the agent token (reinstall from the app mints + stores a new
one on both sides) and delete the server entry in the app. In-app, the
server card goes unreachable — that is the expected closed loop.
