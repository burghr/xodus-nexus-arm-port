#!/bin/bash
# Remove what install.sh added, and the Steam shortcuts for Xodus Nexus.
# Your games, the Xodus Nexus settings and sign-in, your KDE wallet, and
# Google Chrome stay, unless you use the options below.
# https://github.com/burghr/xodus-nexus-armada-arm

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_SCRIPT="$HOME/.local/bin/xodus-nexus-fex"
NEXUS_CONFIG="$HOME/.config/xodus-nexus"
NEXUS_DATA="$HOME/.local/share/xodus-nexus"

REMOVE_DATA=0
REMOVE_GAMES=0
ASSUME_YES=0

usage() {
  cat <<EOF
Usage: ./uninstall.sh [options]

  --remove-data    Also remove the Xodus Nexus settings, the sign-in, the
                   runtimes, and the Wine prefixes of the games.
  --remove-games   Also remove the games that Xodus Nexus installed.
  -y, --yes        Answer yes to all questions.
  -h, --help       Show this help.

Your KDE wallet and Google Chrome always stay.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --remove-data) REMOVE_DATA=1 ;;
    --remove-games) REMOVE_GAMES=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

confirm() {
  [ "$ASSUME_YES" = 1 ] && return 0
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" =~ ^[Yy] ]]
}

if pgrep -x steam >/dev/null; then
  echo "Close Steam first, so that the Steam shortcuts can be removed." >&2
  exit 1
fi
if pgrep -f '[x]odus-nexus\.bin' >/dev/null; then
  echo "Close Xodus Nexus first." >&2
  exit 1
fi

# Print the game folders from the Nexus state. Only folders in the Nexus game
# folder, and not imported games, because the user put those there.
game_folders() {
  python3 -I - "$NEXUS_CONFIG/launcher-state.json" <<'EOF'
import json, os, sys
try:
    state = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(0)
default = os.path.join(os.path.expanduser("~"), "Games", "Xodus Nexus")
root = os.path.realpath((state.get("settings") or {}).get("installRoot") or default)
for game in state.get("games") or []:
    folder = game.get("path")
    if not isinstance(folder, str) or game.get("installState") == "imported":
        continue
    folder = os.path.realpath(folder)
    if folder != root and folder.startswith(root + os.sep) and os.path.isdir(folder):
        print(folder)
EOF
}

# Read the game folders before --remove-data deletes the Nexus state.
folders=()
if [ "$REMOVE_GAMES" = 1 ]; then
  while IFS= read -r folder; do folders+=("$folder"); done < <(game_folders)
  if [ "${#folders[@]}" = 0 ]; then
    echo "No installed games found."
    REMOVE_GAMES=0
  else
    echo "These game folders will be removed:"
    printf '  %s\n' "${folders[@]}"
    confirm "Remove these games? This cannot be undone." || REMOVE_GAMES=0
  fi
fi
if [ "$REMOVE_DATA" = 1 ]; then
  echo "This removes the Xodus Nexus settings, the sign-in, the runtimes, and the"
  echo "Wine prefixes in $NEXUS_DATA. Save games that are only in a prefix are lost."
  confirm "Remove the Xodus Nexus data? This cannot be undone." || REMOVE_DATA=0
fi

# The start script shortcuts, and the Nexus game shortcuts, which start an
# AppImage that is removed next.
python3 -I "$SRC_DIR/steam_shortcut.py" remove --exe "$START_SCRIPT" || true
python3 -I "$SRC_DIR/steam_shortcut.py" remove-nexus || true
rm -f "$START_SCRIPT" "$HOME/.local/share/applications/xodus-nexus-fex.desktop"
rm -rf "$HOME/.local/lib/xodus-x86_64" "$HOME/.local/share/xodus-nexus-fex"
echo "Removed the Xodus Nexus AppImage, the start script, and the shortcuts."

if [ "$REMOVE_GAMES" = 1 ]; then
  for folder in "${folders[@]}"; do rm -rf -- "$folder"; done
  echo "Removed ${#folders[@]} game(s)."
fi
if [ "$REMOVE_DATA" = 1 ]; then
  rm -rf -- "$NEXUS_CONFIG" "$NEXUS_DATA"
  echo "Removed the Xodus Nexus data."
fi
if [ "$REMOVE_DATA" = 0 ] && [ "$REMOVE_GAMES" = 0 ]; then
  echo "Your games and the Xodus Nexus settings stay. See ./uninstall.sh --help."
fi
