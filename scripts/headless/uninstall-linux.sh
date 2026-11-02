#!/usr/bin/env bash
# MyControlPanel headless poll — manual per-user uninstall (TM-1, Lina).
# Usage:
#   ./uninstall-linux.sh
set -euo pipefail
systemctl --user disable --now mcp-poll.timer || true
rm -f "$HOME/.config/systemd/user/mcp-poll.service" "$HOME/.config/systemd/user/mcp-poll.timer"
systemctl --user daemon-reload || true
echo "Removed user timer mcp-poll.timer"
