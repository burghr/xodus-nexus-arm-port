#!/bin/bash
# Remove what install.sh added. Your KDE wallet, Google Chrome, your games,
# and the Xodus Nexus settings in ~/.config/xodus-nexus stay as they are.
# https://github.com/burghr/xodus-nexus-armada

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_SCRIPT="$HOME/.local/bin/xodus-nexus-fex"

if pgrep -x steam >/dev/null; then
  echo "Close Steam first, so that the Steam shortcut can be removed." >&2
  exit 1
fi

python3 -I "$SRC_DIR/steam_shortcut.py" remove --exe "$START_SCRIPT" || true
rm -f "$START_SCRIPT" "$HOME/.local/share/applications/xodus-nexus-fex.desktop"
rm -rf "$HOME/.local/lib/xodus-x86_64" "$HOME/.local/share/xodus-nexus-fex"

echo "Removed. To remove the Xodus Nexus settings too, delete ~/.config/xodus-nexus."
