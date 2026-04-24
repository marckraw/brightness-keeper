#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
"$SCRIPT_DIR/brightness-keeper" --level 100 --display-services --m1ddc --m1ddc-display 1

printf "\nDone. Press any key to close this window."
read -rs -k 1
