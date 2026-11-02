#!/usr/bin/env bash
# mcpoll headless poll — manual per-user install for macOS (Lisa, TM-1 follow-up).
# Copies the LaunchAgent plist, loads it. No sudo, no root.
#
# Prerequisites: build the binary once and write a servers file, e.g.
#   dart compile exe bin/mcpoll.dart -o ~/.local/share/mycontrolpanel/mcpoll
#   printf '[{"id":"web","name":"web","host":"192.168.1.10"}]' \
#     > ~/.local/share/mycontrolpanel/servers.json
#
# Usage:
#   ./install-macos.sh [/path/to/install-dir]
set -euo pipefail
INSTALL_DIR="${1:-$HOME/.local/share/mycontrolpanel}"
AGENT_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$AGENT_DIR"
sed "s|@INSTALL_DIR@|$INSTALL_DIR|g" "$(dirname "$0")/macos/com.mycontrolpanel.mcpoll.plist" > "$AGENT_DIR/com.mycontrolpanel.mcpoll.plist"
chmod 0600 "$AGENT_DIR/com.mycontrolpanel.mcpoll.plist"
launchctl unload "$AGENT_DIR/com.mycontrolpanel.mcpoll.plist" 2>/dev/null || true
launchctl load "$AGENT_DIR/com.mycontrolpanel.mcpoll.plist"
echo "Installed LaunchAgent com.mycontrolpanel.mcpoll (runs: $INSTALL_DIR/mcpoll --consent --servers $INSTALL_DIR/servers.json)"
