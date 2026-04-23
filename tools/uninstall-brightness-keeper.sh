#!/usr/bin/env zsh
set -euo pipefail

LABEL="com.convergence.brightness-keeper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

echo "Removed $LABEL"
