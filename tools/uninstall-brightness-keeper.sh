#!/usr/bin/env zsh
set -euo pipefail

LABELS=("com.brightness-keeper" "com.convergence.brightness-keeper")

for label in "${LABELS[@]}"; do
  plist="$HOME/Library/LaunchAgents/$label.plist"
  launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
  rm -f "$plist"
  echo "Removed $label"
done
