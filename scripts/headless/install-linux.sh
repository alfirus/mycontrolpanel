#!/usr/bin/env bash
# MyControlPanel headless poll — manual per-user install (TM-1, Lina).
# Copies the systemd user unit + timer, enables the timer. No sudo, no root.
# Managed lifecycle (verify/status/ledger): Zara owns (t_13eee02b).
#
# Usage:
#   ./install-linux.sh [/path/to/install-dir]
set -euo pipefail
INSTALL_DIR="${1:-$HOME/.local/share/mycontrolpanel}"
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
sed "s|@INSTALL_DIR@|$INSTALL_DIR|g" "$(dirname "$0")/linux/mcp-poll.service" > "$UNIT_DIR/mcp-poll.service"
cp "$(dirname "$0")/linux/mcp-poll.timer" "$UNIT_DIR/mcp-poll.timer"
chmod 0600 "$UNIT_DIR/mcp-poll.service" "$UNIT_DIR/mcp-poll.timer"
systemctl --user daemon-reload
systemctl --user enable --now mcp-poll.timer
echo "Installed user timer mcp-poll.timer (runs: $INSTALL_DIR/mycontrolpanel --poll-headless)"
