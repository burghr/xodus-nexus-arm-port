#!/bin/bash
# Remove what install.sh added, and the Steam shortcuts for Xodus Nexus.
# Your games, the Xodus Nexus settings and sign-in, your KDE wallet, and
# Google Chrome stay, unless you use the options below.
# https://github.com/burghr/xodus-nexus-arm-port

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

  --remove-data    Also sign out of Xodus Nexus, and remove its settings, the
                   runtimes, and the Wine prefixes of the games.
  --remove-games   Also remove the games that Xodus Nexus downloaded. Other
                   folders in the game folder, for example imported games,
                   are removed only if you answer yes to a separate question.
  -y, --yes        Answer yes to the questions. It never removes imported games.
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

# Always ask, also with -y, and answer no when nobody can answer.
confirm_always() {
  local answer=""
  [ -t 0 ] || return 1
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

# Print the game folders in the Nexus game folder, each as a kind and a path,
# NUL-separated. Kind "D": a complete Nexus download used this folder. Kind
# "U": no download record, so it can be an imported game. The game state does
# not say if a game was imported, because Nexus sets "ready" also for complete
# imported games. Paths with a newline are skipped.
game_folders() {
  python3 -I - "$NEXUS_CONFIG/launcher-state.json" <<'EOF'
import json, os, sys
try:
    state = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(0)
default = os.path.join(os.path.expanduser("~"), "Games", "Xodus Nexus")
root = os.path.realpath((state.get("settings") or {}).get("installRoot") or default)

def inside(value):
    if not isinstance(value, str) or "\n" in value or "\0" in value:
        return None
    folder = os.path.realpath(value)
    if folder != root and folder.startswith(root + os.sep) and os.path.isdir(folder):
        return folder
    return None

downloaded = set()
for task in state.get("downloads") or []:
    folder = inside(task.get("destination")) if task.get("status") == "complete" else None
    if folder:
        downloaded.add(folder)
seen = set()
for game in state.get("games") or []:
    folder = inside(game.get("path"))
    if not folder or folder in seen:
        continue
    seen.add(folder)
    sys.stdout.write(("D" if folder in downloaded else "U") + "\0" + folder + "\0")
EOF
}

# The backend's own sign-out, the same as "Sign out" in Settings. It removes
# the sign-in from the KDE wallet. Run it before the backend is removed.
sign_out() {
  local cli
  cli=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("binaryPath",""))' \
    "$NEXUS_CONFIG/xodus-backends/current.json" 2>/dev/null || true)
  if [ -z "$cli" ] || [ ! -x "$cli" ]; then
    echo "No Nexus backend found, so the sign-in in the KDE wallet was not removed."
    echo "To remove it, open KDE Wallet Manager and delete the Xodus entries."
    return 0
  fi
  echo "Sign out of Xodus Nexus. A KDE window can ask for your wallet password."
  if timeout 120 "$cli" logout --device >/dev/null 2>&1; then
    echo "Signed out. The sign-in was removed from the KDE wallet."
  else
    echo "The sign-out did not complete, so the sign-in can still be in the KDE wallet."
    echo "To remove it, open KDE Wallet Manager and delete the Xodus entries."
  fi
}

# Read the game folders before --remove-data deletes the Nexus state.
folders=()
if [ "$REMOVE_GAMES" = 1 ]; then
  downloaded=() other=()
  while IFS= read -r -d '' kind && IFS= read -r -d '' folder; do
    if [ "$kind" = D ]; then downloaded+=("$folder"); else other+=("$folder"); fi
  done < <(game_folders)
  if [ "${#downloaded[@]}" -gt 0 ]; then
    echo "These games were downloaded by Xodus Nexus:"
    printf '  %s\n' "${downloaded[@]}"
    if confirm "Remove these games? This cannot be undone."; then
      folders+=("${downloaded[@]}")
    fi
  fi
  if [ "${#other[@]}" -gt 0 ]; then
    echo "These folders are in the Xodus Nexus game folder, but no download record"
    echo "shows that Xodus Nexus installed them. They can be games that you imported:"
    printf '  %s\n' "${other[@]}"
    if confirm_always "Also remove these folders? This cannot be undone."; then
      folders+=("${other[@]}")
    else
      echo "Kept these folders."
    fi
  fi
  [ "${#downloaded[@]}" -gt 0 ] || [ "${#other[@]}" -gt 0 ] || echo "No installed games found."
  [ "${#folders[@]}" -gt 0 ] || REMOVE_GAMES=0
fi
if [ "$REMOVE_DATA" = 1 ]; then
  echo "This signs out of Xodus Nexus, and removes its settings, the runtimes, and the"
  echo "Wine prefixes in $NEXUS_DATA. Save games that are only in a prefix are lost."
  confirm "Remove the Xodus Nexus data? This cannot be undone." || REMOVE_DATA=0
fi

[ "$REMOVE_DATA" = 1 ] && sign_out

# The start script shortcuts, and the Nexus game shortcuts, which start an
# AppImage that is removed next.
python3 -I "$SRC_DIR/steam_shortcut.py" remove --exe "$START_SCRIPT" || true
python3 -I "$SRC_DIR/steam_shortcut.py" remove-nexus || true
rm -f "$START_SCRIPT" "$HOME/.local/share/applications/xodus-nexus-fex.desktop"
rm -rf "$HOME/.local/lib/xodus-x86_64" "$HOME/.local/share/xodus-nexus-fex"
echo "Removed the Xodus Nexus AppImage, the start script, and the shortcuts."

if [ "$REMOVE_GAMES" = 1 ]; then
  for folder in "${folders[@]}"; do rm -rf -- "$folder"; done
  # The backend makes .xodus-chain-* work folders in the game folder when it
  # starts a game. A run that ends badly leaves them. Then remove the game
  # folder too, but only if it is empty now.
  game_root=$(dirname -- "${folders[0]}")
  rm -rf -- "$game_root"/.xodus-chain-*
  rmdir -- "$game_root" 2>/dev/null || true
  echo "Removed ${#folders[@]} game folder(s)."
fi
if [ "$REMOVE_DATA" = 1 ]; then
  rm -rf -- "$NEXUS_CONFIG" "$NEXUS_DATA"
  echo "Removed the Xodus Nexus data."
fi
if [ "$REMOVE_DATA" = 0 ] && [ "$REMOVE_GAMES" = 0 ]; then
  echo "Your games and the Xodus Nexus settings stay. See ./uninstall.sh --help."
fi
