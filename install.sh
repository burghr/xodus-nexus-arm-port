#!/bin/bash
# Install the native arm64 build of Xodus Nexus on ArmadaOS (ARM64).
# The backend, the Wine runtime, and the games are x86_64 and run through FEX.
# https://github.com/burghr/xodus-nexus-armada-arm
#
# Run it in Desktop Mode, in Konsole, as your normal user (not root).
# It is safe to run again: each step skips what is already done, and a new
# arm64 release is downloaded if there is one.

set -euo pipefail

# These paths come from the earlier x86_64 install. Keep them, so that the
# Steam shortcuts of existing installs still work.
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME/.local/share/xodus-nexus-fex"
LIB_DIR="$HOME/.local/lib/xodus-x86_64"
BIN_DIR="$HOME/.local/bin"
START_SCRIPT="$BIN_DIR/xodus-nexus-fex"
APPIMAGE_FILE="$DATA_DIR/Xodus-Nexus.AppImage"
ICON_FILE="$DATA_DIR/xodus-nexus.png"
RELEASES_API="https://api.github.com/repos/burghr/xodus-nexus-arm/releases/latest"
TAG_FILE="$DATA_DIR/arm-release"

APPIMAGE_SOURCE=""
DO_CHROME=1
DO_WALLET=1
DO_STEAM=1
DO_LAUNCH=1
ASSUME_YES=0

usage() {
  cat <<EOF
Usage: ./install.sh [options]

  --appimage PATH   Use this arm64 Xodus Nexus AppImage. Default: download the
                    latest release of burghr/xodus-nexus-arm.
  --no-chrome       Do not install the Google Chrome Flatpak.
  --no-wallet       Do not set up the KDE wallet.
  --no-steam        Do not add the Steam shortcut.
  --no-launch       Do not open Chrome and Xodus Nexus at the end.
  -y, --yes         Answer yes to all questions.
  -h, --help        Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --appimage) APPIMAGE_SOURCE="$2"; shift ;;
    --no-chrome) DO_CHROME=0 ;;
    --no-wallet) DO_WALLET=0 ;;
    --no-steam) DO_STEAM=0 ;;
    --no-launch) DO_LAUNCH=0 ;;
    --fix-shortcuts)
      # Earlier versions needed this after each "Add to Steam".
      echo "The arm64 build does not need --fix-shortcuts. The game shortcuts from \"Add to Steam\" work."
      exit 0 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
confirm() {
  [ "$ASSUME_YES" = 1 ] && return 0
  local answer
  read -r -p "    $1 [y/N] " answer
  [[ "$answer" =~ ^[Yy] ]]
}

secrets_running() {
  [ "$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus NameHasOwner s org.freedesktop.secrets 2>/dev/null)" = "b true" ]
}

check_system() {
  step "Check the system"
  [ "$(id -u)" != 0 ] || fail "Do not run this as root. Run it as your normal user."
  [ "$(uname -m)" = aarch64 ] || fail "This is for ARM64 devices. On x86_64, use the normal Xodus Nexus AppImage."
  [ -e /proc/sys/fs/binfmt_misc/FEX-x86_64 ] \
    || fail "FEX is not registered for x86_64 programs. This installer expects ArmadaOS."
  for tool in curl python3 busctl secret-tool flatpak sha512sum; do
    command -v "$tool" >/dev/null || fail "Missing tool: $tool"
  done
  case "${XDG_CURRENT_DESKTOP:-}" in
    *KDE*) ;;
    *) fail "Run this in Desktop Mode. The wallet and Steam steps need the KDE desktop." ;;
  esac
  info "ARM64 and FEX: OK"
}

# Print x86_64 or arm64 for an ELF file, from its machine field.
elf_arch() {
  case "$(od -An -tu2 -j18 -N2 "$1" 2>/dev/null | tr -d ' ')" in
    62) echo x86_64 ;;
    183) echo arm64 ;;
    *) echo unknown ;;
  esac
}

xodus_running() {
  pgrep -f '[x]odus-nexus\.bin' >/dev/null
}

# Download the latest arm64 AppImage, and check its SHA-512 checksum.
# Save the release tag, so that the next run can find a new release.
download_release() {
  local release url sum_url expected actual tag
  xodus_running && fail "Close Xodus Nexus first, then run this again."
  release=$(curl -fsSL "$RELEASES_API") || fail "Cannot read the latest release from GitHub."
  asset() {
    printf '%s' "$release" | python3 -I -c 'import json,sys; a=[x["browser_download_url"] for x in json.load(sys.stdin)["assets"] if x["name"].endswith(sys.argv[1])]; print(a[0] if a else "")' "$1"
  }
  url=$(asset "-arm64.AppImage")
  [ -n "$url" ] || fail "The latest release has no arm64 AppImage."
  tag=$(printf '%s' "$release" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
  info "Download $(basename "$url") ($tag)"
  curl -fL --progress-bar -o "$APPIMAGE_FILE.tmp" "$url"
  sum_url=$(asset "-arm64.AppImage.sha512sum")
  [ -n "$sum_url" ] || { rm -f "$APPIMAGE_FILE.tmp"; fail "The latest release has no checksum file."; }
  expected=$(curl -fsSL "$sum_url" | awk 'NR == 1 {print $1}')
  actual=$(sha512sum "$APPIMAGE_FILE.tmp" | awk '{print $1}')
  [ "$expected" = "$actual" ] || { rm -f "$APPIMAGE_FILE.tmp"; fail "The SHA-512 checksum of the download is wrong."; }
  [ "$(elf_arch "$APPIMAGE_FILE.tmp")" = arm64 ] || { rm -f "$APPIMAGE_FILE.tmp"; fail "The download is not an arm64 AppImage."; }
  mv -f "$APPIMAGE_FILE.tmp" "$APPIMAGE_FILE"
  printf '%s\n' "$tag" > "$TAG_FILE"
  info "Checksum: OK"
}

install_appimage() {
  step "Install the Xodus Nexus AppImage"
  mkdir -p "$DATA_DIR"
  if [ -n "$APPIMAGE_SOURCE" ]; then
    [ -f "$APPIMAGE_SOURCE" ] || fail "File not found: $APPIMAGE_SOURCE"
    [ "$(elf_arch "$APPIMAGE_SOURCE")" = arm64 ] || fail "$APPIMAGE_SOURCE is not an arm64 AppImage."
    xodus_running && fail "Close Xodus Nexus first, then run this again."
    cp -f "$APPIMAGE_SOURCE" "$APPIMAGE_FILE.tmp"
    mv -f "$APPIMAGE_FILE.tmp" "$APPIMAGE_FILE"
    rm -f "$TAG_FILE"
    chmod +x "$APPIMAGE_FILE"
    info "Copied $APPIMAGE_SOURCE"
    return
  fi

  local installed=none latest current=""
  [ -f "$APPIMAGE_FILE" ] && installed=$(elf_arch "$APPIMAGE_FILE")
  if [ "$installed" = x86_64 ]; then
    # Earlier versions of this installer installed the x86_64 build.
    info "The x86_64 build is installed. This installer now uses the native arm64 build."
    if ! confirm "Replace it with the arm64 build? Your sign-in, settings, games, and Steam shortcuts stay."; then
      info "Kept the x86_64 build. Nothing changed."
      exit 0
    fi
  fi
  # Xodus Nexus can update itself from the same releases, so compare the
  # checksum of the installed file, not a saved release tag.
  local release sum_url latest_sum=""
  release=$(curl -fsSL "$RELEASES_API") || fail "Cannot read the latest release from GitHub."
  latest=$(printf '%s' "$release" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
  sum_url=$(printf '%s' "$release" | python3 -I -c 'import json,sys; a=[x["browser_download_url"] for x in json.load(sys.stdin)["assets"] if x["name"].endswith("-arm64.AppImage.sha512sum")]; print(a[0] if a else "")')
  [ -n "$sum_url" ] && latest_sum=$(curl -fsSL "$sum_url" | awk 'NR == 1 {print $1}')
  [ "$installed" = arm64 ] && current=$(sha512sum "$APPIMAGE_FILE" | awk '{print $1}')
  if [ -n "$latest_sum" ] && [ "$current" = "$latest_sum" ]; then
    info "Already installed: $latest"
    printf '%s\n' "$latest" > "$TAG_FILE"
  else
    download_release
  fi
  chmod +x "$APPIMAGE_FILE"
}

# The x86_64 build needed a copy of the x86_64 NSS libraries. The arm64 build
# uses the libraries of ArmadaOS, so remove the copy.
remove_x86_libraries() {
  ls "$LIB_DIR"/*.so* >/dev/null 2>&1 || return 0
  step "Remove the x86_64 libraries of the earlier install"
  rm -f "$LIB_DIR"/*.so*
  info "Removed. The arm64 build does not need them."
}

install_pkexec_stub() {
  step "Install the pkexec stand-in"
  mkdir -p "$LIB_DIR/bin"
  cat > "$LIB_DIR/bin/pkexec" <<'EOF'
#!/bin/sh
# Xodus Nexus uses "pkexec cat" to read SMBIOS data. ARM devices have no
# SMBIOS data, so fail at once and do not show a password prompt.
exit 1
EOF
  chmod +x "$LIB_DIR/bin/pkexec"
  info "Only Xodus Nexus uses it. Other programs still use the real pkexec."
}

install_start_script() {
  step "Install the start script and menu item"
  mkdir -p "$BIN_DIR" "$HOME/.local/share/applications"
  install -m 755 "$SRC_DIR/xodus-nexus-fex" "$START_SCRIPT"
  if [ ! -f "$ICON_FILE" ]; then
    local tmp
    tmp=$(mktemp -d)
    # The xodus-nexus.png at the AppImage root is a symlink, so extract its target.
    local icon=usr/share/icons/hicolor/512x512/apps/xodus-nexus.png
    (cd "$tmp" && "$APPIMAGE_FILE" --appimage-extract "$icon" >/dev/null 2>&1) || true
    if [ -f "$tmp/squashfs-root/$icon" ]; then
      cp "$tmp/squashfs-root/$icon" "$ICON_FILE"
    else
      info "Could not extract the icon. The shortcuts have no icon."
    fi
    rm -rf "$tmp"
  fi
  cat > "$HOME/.local/share/applications/xodus-nexus-fex.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Xodus Nexus
Exec=$START_SCRIPT
Icon=$ICON_FILE
Categories=Game;
Terminal=false
EOF
  info "Start script: $START_SCRIPT"
}

install_chrome() {
  step "Install Google Chrome (needed for the Microsoft sign-in)"
  if [ -x /usr/bin/google-chrome-stable ] || [ -x /usr/bin/google-chrome ] \
     || flatpak info --user com.google.Chrome >/dev/null 2>&1 \
     || flatpak info --system com.google.Chrome >/dev/null 2>&1; then
    info "Already installed."
    return
  fi
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y --noninteractive flathub com.google.Chrome
}

wallet_locked() {
  [ "$(busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/aliases/default \
    org.freedesktop.Secret.Collection Locked 2>/dev/null)" = "b true" ]
}

try_empty_unlock() {
  local collection=/org/freedesktop/secrets/aliases/default reply prompt
  reply=$(busctl --user call org.freedesktop.secrets /org/freedesktop/secrets \
    org.freedesktop.Secret.Service Unlock ao 1 "$collection" 2>/dev/null) || return 0
  prompt=$(printf '%s' "$reply" | grep -oE '"/org/freedesktop/secrets/prompt/[^"]+"' | tr -d '"' || true)
  [ -n "$prompt" ] || return 0
  # With a password, this shows a KDE window. Give it a few seconds only:
  # a typed password is not the goal, so do not wait for one.
  busctl --user call org.freedesktop.secrets "$prompt" \
    org.freedesktop.Secret.Prompt Prompt s "" >/dev/null 2>&1 || true
  sleep 3
  busctl --user call org.freedesktop.secrets "$prompt" \
    org.freedesktop.Secret.Prompt Dismiss >/dev/null 2>&1 || true
}

setup_wallet() {
  step "Set up the KDE wallet"
  if ! secrets_running; then
    info "Start the KDE wallet service."
    # Ask D-Bus to start ksecretd. If that does not work, start it directly.
    busctl --user call org.kde.secretservicecompat / org.freedesktop.DBus.Peer Ping >/dev/null 2>&1 \
      || { [ -x /usr/bin/ksecretd ] && setsid /usr/bin/ksecretd >/dev/null 2>&1 </dev/null & }
    local i=0
    while [ "$i" -lt 15 ] && ! secrets_running; do
      sleep 1
      i=$((i + 1))
    done
  fi
  secrets_running || fail "The KDE wallet service (ksecretd) does not run. Enable KDE Wallet, then run this again."

  local alias
  alias=$(busctl --user call org.freedesktop.secrets /org/freedesktop/secrets \
    org.freedesktop.Secret.Service ReadAlias s default 2>/dev/null | awk '{print $2}' | tr -d '"')
  if [ -z "$alias" ] || [ "$alias" = "/" ]; then
    info "You have no wallet yet. Xodus Nexus keeps your Microsoft sign-in in it."
    info "Choose how to protect it:"
    info "  - No password: nothing to type. Each program that runs as your user,"
    info "    and each person with the device files, can read the sign-in."
    info "  - A password: the wallet is encrypted. After each start of the device,"
    info "    Xodus Nexus asks for the password one time. In Game Mode, press"
    info "    Steam + X for the on-screen keyboard."
    local use_password=0
    # -y keeps the earlier behavior: a wallet with no password.
    if [ "$ASSUME_YES" != 1 ] && confirm "Use a wallet password?"; then
      use_password=1
    fi
    info "A KDE Wallet window opens now. In that window:"
    info "  1. Select Classic (not GPG)."
    if [ "$use_password" = 1 ]; then
      info "  2. Type your new password in both password fields."
    else
      info "  2. Leave the password fields EMPTY."
    fi
    printf 'xodus-nexus-armada' | secret-tool store --label="xodus-nexus-armada setup" app xodus-nexus-armada-setup \
      || fail "The wallet was not created."
    secret-tool clear app xodus-nexus-armada-setup || true
    info "Wallet created."
    return
  fi

  # An unlock request with no password window succeeds only when the
  # password is empty. A locked wallet with a password stays locked.
  if wallet_locked; then
    try_empty_unlock
    if ! wallet_locked; then
      info "Your wallet has no password."
      return
    fi
    info "Your wallet has a password. After each start of the device, Xodus Nexus"
    info "asks for it one time. In Game Mode, press Steam + X for the on-screen keyboard."
  else
    info "Your wallet is unlocked now, so this cannot test for a password."
    info "With a password, Xodus Nexus asks for it one time after each start of the device."
    return
  fi
  # Only on request: a password is a valid choice, so -y never removes it.
  [ "$ASSUME_YES" = 1 ] && return 0
  confirm "Remove the wallet password? A KDE window asks for the old password." || return 0
  info "In the KDE window, type the old password, then leave the new password fields EMPTY."
  busctl --user --timeout=300 call org.kde.ksecretd /ksecretd org.kde.kwalletcompat \
    changePassword sxs "$(basename "$alias" | sed 's/_20/ /g')" 0 "Xodus Nexus" >/dev/null \
    || info "The password change did not complete. You can run this again later."
}

steam_command() {
  if command -v steam >/dev/null; then echo steam
  else echo "$HOME/.local/share/Steam/steamrtarm64/steam"
  fi
}

# Steam overwrites shortcuts.vdf when it closes, so close it first.
# Return 1 if the user does not want to close Steam.
STEAM_CLOSED=0
close_steam() {
  pgrep -x steam >/dev/null || return 0
  info "Steam must be closed while its shortcuts change."
  confirm "Close Steam now? It opens again after." || { info "Skipped. Run this again when Steam is closed."; return 1; }
  "$(steam_command)" -shutdown >/dev/null 2>&1 || true
  local i=0
  while pgrep -x steam >/dev/null && [ "$i" -lt 30 ]; do sleep 2; i=$((i + 1)); done
  pgrep -x steam >/dev/null && fail "Steam did not close."
  STEAM_CLOSED=1
}

reopen_steam() {
  [ "$STEAM_CLOSED" = 1 ] || return 0
  if [ -x /usr/libexec/armada/launch-steam ]; then
    setsid /usr/libexec/armada/launch-steam --desktop >/dev/null 2>&1 </dev/null &
  else
    setsid "$(steam_command)" >/dev/null 2>&1 </dev/null &
  fi
  STEAM_CLOSED=0
  info "Steam is opening again."
}

add_steam_shortcut() {
  step "Add Xodus Nexus to Steam"
  [ -d "$HOME/.local/share/Steam/userdata" ] || { info "Steam has no user yet. Sign in to Steam, then run this again."; return; }
  close_steam || return 0
  python3 -I "$SRC_DIR/steam_shortcut.py" add --name "Xodus Nexus" --exe "$START_SCRIPT" --icon "$ICON_FILE"
  reopen_steam
}

open_chrome_once() {
  step "Open Google Chrome one time"
  local installation=""
  if flatpak info --user com.google.Chrome >/dev/null 2>&1; then installation=--user
  elif flatpak info --system com.google.Chrome >/dev/null 2>&1; then installation=--system
  fi
  if [ -z "$installation" ]; then
    info "Chrome is not installed as a Flatpak. Skipped."
    return
  fi
  if [ -f "$DATA_DIR/chrome-opened" ]; then
    info "Already done."
    return
  fi
  # The sign-in does not work until the Chrome terms are accepted one time.
  info "Chrome opens now. Accept its terms, then close Chrome to continue."
  flatpak run "$installation" com.google.Chrome >/dev/null 2>&1 </dev/null || true
  touch "$DATA_DIR/chrome-opened"
  # Chrome can still be closing after its window closes. Wait for it.
  local i=0
  while [ "$i" -lt 15 ] && flatpak ps --columns=application 2>/dev/null | grep '^com\.google\.Chrome$' >/dev/null; do
    sleep 1
    i=$((i + 1))
  done
}

open_xodus() {
  step "Open Xodus Nexus"
  if xodus_running; then
    info "Xodus Nexus is already open. Sign in there."
    return
  fi
  # Start it as its own systemd unit, like the app menu does. A background
  # job of this script would keep its signal settings and terminal.
  systemd-run --user --collect --quiet --unit="xodus-nexus-$$" "$START_SCRIPT" 2>/dev/null \
    || setsid "$START_SCRIPT" >/dev/null 2>&1 </dev/null &
  info "Wait for Xodus Nexus to open."
  local i=0
  while [ "$i" -lt 20 ] && ! xodus_running; do sleep 1; i=$((i + 1)); done
  sleep 3
  if xodus_running; then
    info "Xodus Nexus is open. Sign in there."
    return
  fi
  info "Xodus Nexus did not open. Open \"Xodus Nexus\" from the app menu."
  info "If it still does not open, run $START_SCRIPT in Konsole and read the error."
}

check_system
install_appimage
remove_x86_libraries
install_pkexec_stub
install_start_script
[ "$DO_CHROME" = 1 ] && install_chrome
[ "$DO_WALLET" = 1 ] && setup_wallet
[ "$DO_STEAM" = 1 ] && add_steam_shortcut
if [ "$DO_LAUNCH" = 1 ]; then
  open_chrome_once
  open_xodus
fi

step "Done"
if [ "$DO_LAUNCH" = 1 ]; then
  info "1. Sign in to Xodus Nexus one time in Desktop Mode."
else
  info "1. Open \"Xodus Nexus\" from the app menu, then sign in one time."
fi
info "2. In Xodus Nexus, open Settings, then select \"Install Nexus runtime\"."
info "   Games do not start without the runtime. Do this one time."
info "3. In Game Mode, start \"Xodus Nexus\" from your Steam library."
info "4. Xodus Nexus shows new updates when it starts. Install them in Settings."
