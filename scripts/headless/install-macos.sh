#!/usr/bin/env bash
# MyControlPanel headless poll — manual per-user install (TM-1, Lina).
# Copies the LaunchAgent plist (mode 0600) and bootstraps it. No sudo, no
# LaunchDaemon. Menu-bar helper scope: Elizabeth owns (t_a0fe4895).
#
# Usage:
#   ./install-macos.sh [/path/to/install-dir]
set -euo pipefail
INSTALL_DIR="${1:-/Applications/MyControlPanel.app/Contents/MacOS}"
AGENT_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$AGENT_DIR"
sed "s|@INSTALL_DIR@|$INSTALL_DIR|g" "$(dirname "$0")/macos/com.mycontrolpanel.poll.plist" > "$AGENT_DIR/com.mycontrolpanel.poll.plist"
chmod 0600 "$AGENT_DIR/com.mycontrolpanel.poll.plist"
launchctl bootstrap "gui/$(id -u)" "$AGENT_DIR/com.mycontrolpanel.poll.plist" 2>/dev/null || \
launchctl load "$AGENT_DIR/com.mycontrolpanel.poll.plist"
echo "Installed LaunchAgent com.mycontrolpanel.poll (runs: $INSTALL_DIR/mycontrolpanel --poll-headless)"
