#!/bin/sh
# Idempotent install / upgrade / health-check / rollback for the
# MyControlPanel metrics agent (:9108) over SSH.
#
# The canonical agent source lives in the Flutter app
# (AgentService.agentScript); export it to a file first, or pass your own
# with --agent-file. The systemd unit defaults to agent/mcp-agent.service.
#
# Privileged host steps (writing /etc/systemd/system, systemctl,
# firewall) run on the SERVER via `sudo -n`. If the server user lacks
# passwordless sudo the script stops with the exact manual commands —
# see docs/runbooks/agent-lifecycle.md. This script never needs local sudo.
#
# Usage:
#   scripts/install-agent.sh --host example.com --user deploy [--port 22]
#     [--identity ~/.ssh/id_ed25519] [--agent-file /tmp/agent.py]
#     [--unit-file agent/mcp-agent.service] [--check-only] [--rollback]
#
# Exit codes: 0 ok, 1 usage/ssh error, 2 health check failed, 3 sudo missing.
set -u

HOST=""; USER=""; PORT="22"; IDENTITY=""; CHECK_ONLY=0; ROLLBACK=0
AGENT_FILE=""; UNIT_FILE=""; REMOTE_DIR="/opt/mcp-agent"; AGENT_PORT="9108"

usage() {
  sed -n '2,/^#$/p' "$0" | sed 's/^# \{0,1\}//'; exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    --agent-file) AGENT_FILE="$2"; shift 2 ;;
    --unit-file) UNIT_FILE="$2"; shift 2 ;;
    --check-only) CHECK_ONLY=1; shift ;;
    --rollback) ROLLBACK=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown flag: $1" >&2; usage ;;
  esac
done

[ -n "$HOST" ] && [ -n "$USER" ] || usage

# Resolve repo-relative defaults (script lives in <repo>/scripts/).
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -z "$UNIT_FILE" ] && UNIT_FILE="$SCRIPT_DIR/../agent/mcp-agent.service"
[ -z "$AGENT_FILE" ] && AGENT_FILE="$SCRIPT_DIR/../agent/agent.py"

SSH="ssh -p $PORT -o BatchMode=yes -o ConnectTimeout=10"
[ -n "$IDENTITY" ] && SSH="$SSH -i $IDENTITY"
SSH="$SSH $USER@$HOST"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit "$2"; }

# --- 1. connectivity -------------------------------------------------------
log "-> ssh $USER@$HOST:$PORT ..."
$SSH 'echo SSH_OK' >/dev/null 2>&1 \
  || fail "ssh failed (key auth? host reachable?). Hint: ssh -p $PORT $USER@$HOST" 1
log "   ssh ok."

remote_health() {
  # $1 = base url host part; run from operator machine.
  curl -fsS --max-time 10 "http://$1:$AGENT_PORT/metrics" 2>/dev/null
}

# --- 2a. check-only ---------------------------------------------------------
if [ "$CHECK_ONLY" = "1" ]; then
  BODY=$(remote_health "$HOST") \
    || fail "health check failed: http://$HOST:$AGENT_PORT/metrics unreachable (firewall? service down?)" 2
  log "   metrics ok: $(printf '%s' "$BODY" | head -c 200)"
  $SSH "systemctl is-active mcp-agent" 2>/dev/null \
    || log "   note: systemctl state unreadable (needs login session, non-fatal)."
  log "CHECK_OK"
  exit 0
fi

# --- 2b. rollback -----------------------------------------------------------
if [ "$ROLLBACK" = "1" ]; then
  log "-> rollback to newest backup ..."
  $SSH "ls -t $REMOTE_DIR/agent.py.bak.* 2>/dev/null | head -n 1" > /tmp/mcp_rb 2>&1 \
    || fail "ssh failed during rollback" 1
  BK=$(cat /tmp/mcp_rb); rm -f /tmp/mcp_rb
  [ -n "$BK" ] || fail "no backup found in $REMOTE_DIR (nothing to roll back to)" 1
  log "   restoring $BK"
  $SSH "sudo -n cp $BK $REMOTE_DIR/agent.py && sudo -n systemctl daemon-reload && sudo -n systemctl restart mcp-agent && sleep 2 && sudo -n systemctl is-active mcp-agent" \
    || fail "rollback restart failed — manual steps in docs/runbooks/agent-lifecycle.md" 3
  sleep 2
  remote_health "$HOST" >/dev/null \
    || fail "rollback applied but /metrics still unreachable" 2
  log "ROLLBACK_OK ($BK)"
  exit 0
fi

# --- 3. install / upgrade ---------------------------------------------------
[ -f "$AGENT_FILE" ] || fail "agent file not found: $AGENT_FILE (export AgentService.agentScript, or pass --agent-file)" 1
[ -f "$UNIT_FILE" ] || fail "unit file not found: $UNIT_FILE" 1

$SSH 'command -v python3 >/dev/null && python3 --version' \
  || fail "python3 missing on $HOST (install it first, then re-run)" 1
$SSH 'sudo -n true 2>/dev/null' \
  || fail "passwordless sudo missing for $USER@$HOST. Manual path: see docs/runbooks/agent-lifecycle.md (sudoers.d entry), then re-run." 3
log "   python3 + passwordless sudo confirmed."

LOCAL_SUM=$(sha256sum "$AGENT_FILE" | cut -d' ' -f1)
REMOTE_SUM=$($SSH "sha256sum $REMOTE_DIR/agent.py 2>/dev/null | cut -d' ' -f1" || true)
if [ "$LOCAL_SUM" = "$REMOTE_SUM" ] && [ -n "$REMOTE_SUM" ]; then
  log "   agent.py already current (sha256 $LOCAL_SUM) — skipping upload."
else
  [ -n "$REMOTE_SUM" ] && log "   installed version differs ($REMOTE_SUM) — backing up before upgrade."
  TS=$(date -u +%Y%m%dT%H%M%SZ)
  $SSH "sudo -n mkdir -p $REMOTE_DIR && [ -f $REMOTE_DIR/agent.py ] && sudo -n cp $REMOTE_DIR/agent.py $REMOTE_DIR/agent.py.bak.$TS || true" \
    || fail "could not prepare $REMOTE_DIR" 3
  log "   uploading agent.py ..."
  scp -P "$PORT" ${IDENTITY:+-i "$IDENTITY"} "$AGENT_FILE" "$USER@$HOST:/tmp/mcp-agent.py" >/dev/null \
    || fail "scp upload failed" 1
  $SSH "sudo -n install -m 644 /tmp/mcp-agent.py $REMOTE_DIR/agent.py && rm -f /tmp/mcp-agent.py" \
    || fail "could not install agent.py into $REMOTE_DIR" 3
  log "   uploaded (sha256 $LOCAL_SUM)."
fi

log "   installing systemd unit ..."
scp -P "$PORT" ${IDENTITY:+-i "$IDENTITY"} "$UNIT_FILE" "$USER@$HOST:/tmp/mcp-agent.service" >/dev/null \
  || fail "scp unit upload failed" 1
$SSH "sudo -n install -m 644 /tmp/mcp-agent.service /etc/systemd/system/mcp-agent.service && rm -f /tmp/mcp-agent.service && sudo -n systemctl daemon-reload && sudo -n systemctl enable --now mcp-agent && sleep 2 && sudo -n systemctl is-active mcp-agent" \
  || fail "systemd enable/start failed — journal: ssh $USER@$HOST journalctl -u mcp-agent" 3
log "   service active."

$SSH "command -v ufw >/dev/null && sudo -n ufw allow $AGENT_PORT/tcp >/dev/null 2>&1 || true; echo FW_DONE" >/dev/null 2>&1 || true

sleep 2
BODY=$(remote_health "$HOST") \
  || fail "installed but http://$HOST:$AGENT_PORT/metrics unreachable from here (cloud security group / firewall? open TCP $AGENT_PORT)" 2
log "   metrics ok: $(printf '%s' "$BODY" | head -c 200)"
log "INSTALL_OK"
