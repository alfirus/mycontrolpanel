# Setup + Operations Guide

End-to-end: connect a server, install the metrics agent, and keep it
healthy. For the wire contract itself, see the
[Metrics Agent API reference](agent-api.md).

## 1. Prerequisites

- The app: `flutter pub get`, then `flutter run -d macos` (or windows /
  linux / ios / android). Release builds: `flutter build macos --release`
  (also `windows`, `linux`, `apk`, `ipa` — macOS + Xcode for the last).
- A target Linux server with **Python 3** (`python3 --version` over SSH —
  the one-click installer checks this first and aborts otherwise).
- SSH access to that server (password **or** key).
- **Passwordless sudo** for the SSH user if you want the one-click install
  (see §3). Otherwise use the guided manual install (§4).

## 2. SSH keys

Settings → Add Server accepts password auth, a key file, or pasted PEM
content.

- **Import via the file picker** (recommended). On macOS the sandbox
  entitlements allow `network.client`, `files.user-selected.read-only`,
  and `files.downloads.read-only` — so a typed `~/.ssh/…` path **cannot**
  be read. Import the key with the picker (its content is stored) or paste
  the PEM text directly.
- Encrypted keys are supported: the app prompts for the passphrase, which
  unlocks the key in memory only (`SshKeyLoader`; nothing is written to
  disk). If install reports `SSH_KEY_NEEDS_PASSPHRASE` /
  `SSH_KEY_BAD_PASSPHRASE`, re-enter it — or fall back to the manual
  install, where you type sudo password yourself.
- If the key cannot be loaded at all, install returns `SSH_KEY_AUTH`:
  switch to the guided manual install rather than retrying.

Secrets (server credentials, PATs, AI keys, SSH key content) live in the
OS keychain/keystore via `flutter_secure_storage`, with a one-time
migration from legacy `SharedPreferences` (`SecureStore.migrateIfNeeded`,
flag `secrets_migrated_v1`). On Linux, install `libsecret-1-dev` so the
secure store works.

## 3. Agent install (one-click)

Tap the install button on a server card. Over SSH the installer:

1. Connects (10s timeout, 20s auth budget) and checks `python3 --version`.
2. Verifies **passwordless sudo** (`sudo -n true`). If it is missing, the
   install stops with the exact fix to run as root:
   `echo "<user> ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/<user>`
   — it never hangs on a sudo prompt.
3. Uploads the stdlib-only agent to `/opt/mcp-agent/agent.py` via stdin
   (no network download needed on the server).
4. Writes the systemd unit and enables it:

```ini
[Unit]
Description=MyControlPanel metrics agent
After=network.target
[Service]
ExecStart=/usr/bin/python3 /opt/mcp-agent/agent.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
```

5. Reloads systemd, enables + starts `mcp-agent`, and checks it is active.
6. Opens TCP **9108** on the host firewall (best-effort `ufw` /
   `firewall-cmd`; non-fatal if no local firewall is present — **cloud
   security groups still need a manual rule**).
7. Verifies `GET http://<host>:9108/metrics` from the app machine and
   prints the returned `cpu / ram / disk / uptime_days`.

If step 7 fails with the agent installed, the port is reachable from the
server but not from here: add the security-group / firewall rule for TCP
9108 and tap VERIFY again.

## 4. Manual install (guided)

For hosts without passwordless sudo, or when one-click reports
`SSH_KEY_AUTH`. The app shows server-specific steps plus a single
base64-embedded command (agent + unit, no download required):

1. SSH in from any machine: `ssh -i <your-key.pem> -p <port> <user>@<host>`.
2. Paste the install command, press Enter.
3. Expect `AGENT_OK` plus JSON like `{"cpu":0.1,...}`.
4. Ensure TCP 9108 is open to the app machine, then tap VERIFY.

Equivalent raw command (the app generates the same thing with the real
payloads embedded):

```bash
sudo mkdir -p /opt/mcp-agent \
&& echo <base64-agent.py> | base64 -d | sudo tee /opt/mcp-agent/agent.py > /dev/null \
&& echo <base64-unit> | base64 -d | sudo tee /etc/systemd/system/mcp-agent.service > /dev/null \
&& sudo systemctl daemon-reload \
&& sudo systemctl enable --now mcp-agent \
&& sleep 2 \
&& sudo systemctl is-active mcp-agent \
&& curl -s http://127.0.0.1:9108/metrics && echo && echo AGENT_OK
```

## 5. Cron discovery

Cronjobs are discovered live over SSH on every rescan (manual refresh or
tab switch) — no agent involvement:

| Source          | Command                                                          |
|-----------------|------------------------------------------------------------------|
| User crontab    | `crontab -l` (of the SSH user)                                   |
| System crontab  | `cat /etc/crontab`                                               |
| Drop-ins        | each file in `/etc/cron.d/*` (tagged `###FILE:<path>` per file)  |

Parsing keeps the user field for system sources and supports `@reboot` /
`@daily` style schedules. Structured last-run tracking, a log viewer per
job (journal + syslog grep on the command's program name, 7-day window,
200-line cap), and in-place editing (`crontab -` rewrite for user crons;
`sudo cp -p` backup + rewrite for system files with an exact-one-line
match guard, backups at `<path>.mcp-bak`) are built into the Cronjobs UI.

If discovery returns nothing: the SSH user may lack read access to
`/etc/crontab` / `/etc/cron.d/*`, or the host genuinely has no jobs.

## 6. Troubleshooting

| Symptom | Check |
|---|---|
| Install: `python3 --version` fails | Install Python 3 on the server first |
| Install: passwordless-sudo error | Run the printed `tee /etc/sudoers.d/<user>` fix as root, or use manual install |
| Install: `SSH_KEY_NEEDS_PASSPHRASE` / `SSH_KEY_BAD_PASSPHRASE` | Re-enter the key passphrase (Terminal tab), or use manual install |
| Install: agent installed but `/metrics` unreachable | Open TCP 9108 (host firewall + cloud security group), then VERIFY |
| Metrics stale / grey status dot | `curl -s http://<host>:9108/metrics` from the app machine; `sudo systemctl status mcp-agent` on the server |
| `staleAgent` reinstall banner | Agent v1 still installed (no `version` key) — reinstall |
| macOS: picked key file not readable | Sandbox limitation — import via picker or paste PEM content, never a typed `~/.ssh/…` path |
| Linux: secrets not persisting | Install `libsecret-1-dev` and rebuild |
| Cronjobs empty | Check SSH user read access to `/etc/crontab`, `/etc/cron.d/*` |
| Log viewer empty for a job | Only journal/syslog lines from the last 7 days mentioning the command's program name are searched |
