#!/usr/bin/env bash
# Installs or updates ⌘Tab Wheel from the latest GitHub release. No Xcode, no clone:
#
#   curl -fsSL https://raw.githubusercontent.com/faustienf/tabwheel/main/scripts/download.sh | bash
#
# The app isn't notarized. Downloaded by a browser, macOS won't open it until Privacy & Security
# → Open Anyway; downloaded by curl, it opens like an app built here.
# TABWHEEL_ZIP: another zip to install (a release's own link, or a file:// one).
set -euo pipefail

EXECUTABLE="CmdTabWheel"
APP_NAME="$EXECUTABLE.app"
ZIP="${TABWHEEL_ZIP:-https://github.com/faustienf/tabwheel/releases/latest/download/$EXECUTABLE.zip}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

fail() {
  echo "✗ $*" >&2
  exit 1
}

[ "$(id -u)" -ne 0 ] || fail "run it without sudo"
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "⌘Tab Wheel needs macOS 14 or later"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "▸ downloading $ZIP"
curl -fL --progress-bar -o "$work/app.zip" "$ZIP" || fail "couldn't download it"
ditto -x -k "$work/app.zip" "$work"
[ -d "$work/$APP_NAME" ] || fail "there's no $APP_NAME in the download"
codesign --verify --strict "$work/$APP_NAME" 2>/dev/null || fail "the downloaded app is damaged"
version="v$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$work/$APP_NAME/Contents/Info.plist")"

# A copy already in /Applications or ~/Applications is replaced where it is. Otherwise the app
# goes to /Applications, or to ~/Applications for a user who can't write there.
if [ -d "/Applications/$APP_NAME" ]; then
  dest="/Applications/$APP_NAME"
elif [ -d "$HOME/Applications/$APP_NAME" ]; then
  dest="$HOME/Applications/$APP_NAME"
elif [ -w /Applications ]; then
  dest="/Applications/$APP_NAME"
else
  dest="$HOME/Applications/$APP_NAME"
fi

# SIGTERM = a graceful quit: the app gives ⌘Tab back to macOS on its way out.
if pkill -x -U "$(id -u)" "$EXECUTABLE"; then
  echo "▸ quitting the running ⌘Tab Wheel"
  for _ in $(seq 30); do
    pgrep -x -U "$(id -u)" "$EXECUTABLE" >/dev/null || break
    sleep 0.1
  done
  ! pgrep -x -U "$(id -u)" "$EXECUTABLE" >/dev/null \
    || fail "⌘Tab Wheel didn't quit: quit it from its menu bar icon, then run this again"
fi

if [ -e "$dest" ]; then
  echo "▸ replacing $dest"
  # The old copy is moved out, not deleted in place: if the new one can't get in, it goes back.
  if ! mv "$dest" "$work/old-$APP_NAME"; then
    open "$dest"
    fail "couldn't move the old $dest out of the way.
  If macOS said your terminal was prevented from modifying apps: System Settings → Privacy & Security
  → App Management → turn your terminal on, then run this again."
  fi
  if ! mv "$work/$APP_NAME" "$dest"; then
    mv "$work/old-$APP_NAME" "$dest"
    open "$dest"
    fail "couldn't put the new app into $(dirname "$dest"); the old one is back and running"
  fi
  status="updated"
else
  echo "▸ installing into $(dirname "$dest")"
  mkdir -p "$(dirname "$dest")"
  mv "$work/$APP_NAME" "$dest"
  status="installed"
fi
"$LSREGISTER" -f "$dest"

open "$dest"
echo "✓ ⌘Tab Wheel $version $status: $dest"
if [ "$status" = "installed" ]; then
  echo "  It's in the menu bar now; its setup window asks for the permissions it needs."
fi
