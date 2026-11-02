#!/usr/bin/env bash
# MyControlPanel headless poll — manual per-user uninstall (TM-1, Lina).
# Usage:
#   ./uninstall-macos.sh
set -euo pipefail
PLIST="$HOME/Library/LaunchAgents/com.mycontrolpanel.poll.plist"
launchctl bootout "gui/$(id -u)/com.mycontrolpanel.poll" 2>/dev/null || \
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "Removed LaunchAgent com.mycontrolpanel.poll"
