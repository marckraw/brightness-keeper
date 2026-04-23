#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
"$SCRIPT_DIR/brightness-keeper" --level 100 --fallback-keys

printf "\nDone. Press any key to close this window."
read -rs -k 1
