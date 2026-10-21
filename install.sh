#!/bin/bash
# Install Xodus Nexus for ArmadaOS (ARM64) and run it through FEX.
# https://github.com/burghr/xodus-nexus-armada-arm
#
# Run it in Desktop Mode, in Konsole, as your normal user (not root).
# It is safe to run again: each step skips what is already done.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME/.local/share/xodus-nexus-fex"
LIB_DIR="$HOME/.local/lib/xodus-x86_64"
BIN_DIR="$HOME/.local/bin"
START_SCRIPT="$BIN_DIR/xodus-nexus-fex"
APPIMAGE_FILE="$DATA_DIR/Xodus-Nexus.AppImage"
ICON_FILE="$DATA_DIR/xodus-nexus.png"
RELEASES_API="https://api.github.com/repos/domsvoboda/xodus-nexus/releases/latest"
ARCH_MIRROR="https://geo.mirror.pkgbuild.com/core/os/x86_64"

APPIMAGE_SOURCE=""
DO_CHROME=1
DO_WALLET=1
DO_STEAM=1
DO_LAUNCH=1
ASSUME_YES=0

usage() {
  cat <<EOF
Usage: ./install.sh [options]

  --appimage PATH   Use this Xodus Nexus AppImage. Default: download the latest release.
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
  for tool in curl tar zstd python3 busctl secret-tool flatpak; do
    command -v "$tool" >/dev/null || fail "Missing tool: $tool"
  done
  FEX_ROOTFS=$(python3 -I -c 'import json; print(json.load(open("/usr/share/fex-emu/Config.json"))["Config"]["RootFS"])' 2>/dev/null || true)
  [ -n "$FEX_ROOTFS" ] && [ -d "$FEX_ROOTFS" ] || fail "Cannot find the FEX RootFS in /usr/share/fex-emu/Config.json."
  case "${XDG_CURRENT_DESKTOP:-}" in
    *KDE*) ;;
    *) fail "Run this in Desktop Mode. The wallet and Steam steps need the KDE desktop." ;;
  esac
  info "ARM64, FEX, and the RootFS at $FEX_ROOTFS: OK"
}

install_appimage() {
  step "Install the Xodus Nexus AppImage"
  mkdir -p "$DATA_DIR"
  if [ -n "$APPIMAGE_SOURCE" ]; then
    [ -f "$APPIMAGE_SOURCE" ] || fail "File not found: $APPIMAGE_SOURCE"
    cp -f "$APPIMAGE_SOURCE" "$APPIMAGE_FILE.tmp"
    mv -f "$APPIMAGE_FILE.tmp" "$APPIMAGE_FILE"
    info "Copied $APPIMAGE_SOURCE"
  elif [ -f "$APPIMAGE_FILE" ]; then
    info "Already installed. The launcher updates itself in place."
  else
    local release url sum_url expected actual
    release=$(curl -fsSL "$RELEASES_API") || fail "Cannot read the latest release from GitHub."
    url=$(printf '%s' "$release" | python3 -I -c 'import json,sys; a=[x["browser_download_url"] for x in json.load(sys.stdin)["assets"] if x["name"].endswith("-x86_64.AppImage")]; print(a[0] if a else "")')
    [ -n "$url" ] || fail "The latest release has no x86_64 AppImage."
    info "Download $(basename "$url")"
    curl -fL --progress-bar -o "$APPIMAGE_FILE.tmp" "$url"
    sum_url=$(printf '%s' "$release" | python3 -I -c 'import json,sys; a=[x["browser_download_url"] for x in json.load(sys.stdin)["assets"] if x["name"].endswith("-x86_64.AppImage.sha512sum")]; print(a[0] if a else "")')
    if [ -n "$sum_url" ]; then
      expected=$(curl -fsSL "$sum_url" | awk 'NR == 1 {print $1}')
      actual=$(sha512sum "$APPIMAGE_FILE.tmp" | awk '{print $1}')
      [ "$expected" = "$actual" ] || { rm -f "$APPIMAGE_FILE.tmp"; fail "The SHA-512 checksum of the download is wrong."; }
      info "Checksum: OK"
    fi
    mv -f "$APPIMAGE_FILE.tmp" "$APPIMAGE_FILE"
  fi
  chmod +x "$APPIMAGE_FILE"
}

install_nss() {
  step "Install the x86_64 NSS libraries"
  mkdir -p "$LIB_DIR"
  if [ -f "$LIB_DIR/libnss3.so" ] && [ -f "$LIB_DIR/libnssckbi.so" ] && [ ! -L "$LIB_DIR/libnssckbi.so" ]; then
    info "Already installed."
    return
  fi
  local tmp pkg
  tmp=$(mktemp -d)
  pkg=$(curl -fsSL "$ARCH_MIRROR/" | grep -oE 'nss-[0-9][^"]*-x86_64\.pkg\.tar\.zst' | sed -n 1p)
  [ -n "$pkg" ] || fail "Cannot find the nss package on the Arch mirror."
  info "Download $pkg"
  curl -fsSL -o "$tmp/$pkg" "$ARCH_MIRROR/$pkg"
  tar --zstd -xf "$tmp/$pkg" -C "$tmp" usr/lib
  cp -a "$tmp"/usr/lib/*.so* "$LIB_DIR"/
  rm -rf "$tmp"
  # In the package, libnssckbi.so is a symlink into the RootFS. The host
  # resolves symlinks in the home folder, so use a copy of the real file.
  [ -f "$FEX_ROOTFS/usr/lib/pkcs11/p11-kit-trust.so" ] || fail "p11-kit-trust.so is not in the FEX RootFS."
  rm -f "$LIB_DIR/libnssckbi.so"
  cp "$FEX_ROOTFS/usr/lib/pkcs11/p11-kit-trust.so" "$LIB_DIR/libnssckbi.so"
  info "Installed in $LIB_DIR"
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
Name=Xodus Nexus (FEX)
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
    info "You have no wallet yet. A KDE Wallet window opens now. In that window:"
    info "  1. Select Classic (not GPG)."
    info "  2. Leave the password fields EMPTY."
    info "Game Mode cannot show a password window, so the wallet must have no password."
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
      info "Your wallet has no password. Game Mode can unlock it."
      return
    fi
    info "Your wallet has a password, so Game Mode cannot unlock it."
  else
    info "Your wallet is unlocked now, so this cannot test for a password."
    info "If you are signed out in Game Mode, the wallet has a password. Then run"
    info "this again just after a restart, when the wallet is still locked."
    return
  fi
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

add_steam_shortcut() {
  step "Add Xodus Nexus to Steam"
  [ -d "$HOME/.local/share/Steam/userdata" ] || { info "Steam has no user yet. Sign in to Steam, then run this again."; return; }
  local reopen=0
  if pgrep -x steam >/dev/null; then
    info "Steam must be closed while the shortcut is added."
    confirm "Close Steam now? It opens again after." || { info "Skipped. Run this again when Steam is closed."; return; }
    "$(steam_command)" -shutdown >/dev/null 2>&1 || true
    local i=0
    while pgrep -x steam >/dev/null && [ "$i" -lt 30 ]; do sleep 2; i=$((i + 1)); done
    pgrep -x steam >/dev/null && fail "Steam did not close."
    reopen=1
  fi
  python3 -I "$SRC_DIR/steam_shortcut.py" add --name "Xodus Nexus" --exe "$START_SCRIPT" --icon "$ICON_FILE"
  if [ "$reopen" = 1 ]; then
    if [ -x /usr/libexec/armada/launch-steam ]; then
      setsid /usr/libexec/armada/launch-steam --desktop >/dev/null 2>&1 </dev/null &
    else
      setsid "$(steam_command)" >/dev/null 2>&1 </dev/null &
    fi
    info "Steam is opening again."
  fi
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
}

open_xodus() {
  step "Open Xodus Nexus"
  setsid "$START_SCRIPT" >/dev/null 2>&1 </dev/null &
  info "Xodus Nexus opens in a few seconds. Sign in there."
}

check_system
install_appimage
install_nss
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
  info "1. Open \"Xodus Nexus (FEX)\" from the app menu, then sign in one time."
fi
info "2. In Game Mode, start \"Xodus Nexus\" from your Steam library."
