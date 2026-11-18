#!/usr/bin/env bash
# Installs or updates ⌘Tab HUD from the latest GitHub release. No Xcode, no clone:
#
#   curl -fsSL https://raw.githubusercontent.com/faustienf/tabwheel/main/scripts/download.sh | bash
#
# The app isn't notarized. Downloaded by a browser, macOS won't open it until Privacy & Security
# → Open Anyway; downloaded by curl, it opens like an app built here.
# TABWHEEL_ZIP: another zip to install (a release's own link, or a file:// one).
set -euo pipefail

EXECUTABLE="CmdTabWheel"
APP_NAME="⌘Tab HUD.app" # the file's name is what Finder and System Settings show
OLD_APP_NAME="$EXECUTABLE.app" # its name up to v22: a copy under it gets replaced
ZIP="${TABWHEEL_ZIP:-https://github.com/faustienf/tabwheel/releases/latest/download/$EXECUTABLE.zip}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

fail() {
  echo "✗ $*" >&2
  exit 1
}

[ "$(id -u)" -ne 0 ] || fail "run it without sudo"
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "⌘Tab HUD needs macOS 14 or later"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "▸ downloading $ZIP"
curl -fL --progress-bar -o "$work/app.zip" "$ZIP" || fail "couldn't download it"
mkdir "$work/new"
ditto -x -k "$work/app.zip" "$work/new"
new="$work/new/$APP_NAME"
# Releases up to v22 have it under the old name. Renaming doesn't touch the signature.
[ -d "$new" ] || mv "$work/new/$OLD_APP_NAME" "$new" 2>/dev/null || fail "there's no $APP_NAME in the download"
codesign --verify --strict "$new" 2>/dev/null || fail "the downloaded app is damaged"
version="v$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$new/Contents/Info.plist")"

# A copy already in /Applications or ~/Applications, under the app's name or its old one, is
# replaced where it is. Otherwise the app goes to /Applications, or to ~/Applications for a user
# who can't write there.
old=""
for folder in /Applications "$HOME/Applications"; do
  for name in "$APP_NAME" "$OLD_APP_NAME"; do
    if [ -z "$old" ] && [ -d "$folder/$name" ]; then
      old="$folder/$name"
    fi
  done
done
if [ -n "$old" ]; then
  dest="$(dirname "$old")/$APP_NAME"
elif [ -w /Applications ]; then
  dest="/Applications/$APP_NAME"
else
  dest="$HOME/Applications/$APP_NAME"
fi

# SIGTERM = a graceful quit: the app gives ⌘Tab back to macOS on its way out.
if pkill -x -U "$(id -u)" "$EXECUTABLE"; then
  echo "▸ quitting the running ⌘Tab HUD"
  for _ in $(seq 30); do
    pgrep -x -U "$(id -u)" "$EXECUTABLE" >/dev/null || break
    sleep 0.1
  done
  # Still running: it hangs, or runs under Xcode's debugger, which swallows SIGTERM.
  # Force it, and give ⌘Tab back on its behalf.
  if pgrep -x -U "$(id -u)" "$EXECUTABLE" >/dev/null; then
    pkill -9 -x -U "$(id -u)" "$EXECUTABLE" || true
    sleep 0.3
    "$new/Contents/MacOS/$EXECUTABLE" --restore-native-switcher
  fi
fi

if [ -n "$old" ]; then
  echo "▸ replacing $old"
  # The old copy is moved out, not deleted in place: if the new one can't get in, it goes back.
  if ! mv "$old" "$work/old-$APP_NAME"; then
    open "$old"
    fail "couldn't move the old $old out of the way.
  If macOS said your terminal was prevented from modifying apps: System Settings → Privacy & Security
  → App Management → turn your terminal on, then run this again."
  fi
  if ! mv "$new" "$dest"; then
    mv "$work/old-$APP_NAME" "$old"
    open "$old"
    fail "couldn't put the new app into $(dirname "$dest"); the old one is back and running"
  fi
  status="updated"
else
  echo "▸ installing into $(dirname "$dest")"
  mkdir -p "$(dirname "$dest")"
  mv "$new" "$dest"
  status="installed"
fi
"$LSREGISTER" -f "$dest"

open "$dest"
echo "✓ ⌘Tab HUD $version $status: $dest"
if [ "$status" = "installed" ]; then
  echo "  It's in the menu bar now; its setup window asks for the permissions it needs."
fi
